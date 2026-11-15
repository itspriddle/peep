import Darwin
import Foundation
import os

/// The process runner both custom programs share (`CustomPreprocessor`, `CustomProcessor`):
/// validation, the input limit, the session on a dedicated thread, cancellation, and turning
/// the outcome into text or a `PreprocessorError` attributed to `kind`.
struct CustomProgramRunner: Sendable {
    let configuration: PreprocessorConfiguration
    let kind: CustomProgramKind

    private var logger: Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "peep", category: kind.identifier)
    }

    /// Runs the program on `input` and returns its output (see `CustomPreprocessor.run`).
    func run(input: Data, documentURL: URL?) async throws -> String {
        try Task.checkCancellation()
        let limits = configuration.limits
        guard input.count <= limits.maximumInputBytes else {
            throw fail(PreprocessorError(.inputTooLarge(limit: limits.maximumInputBytes)))
        }
        do throws(PreprocessorExecutableError) {
            try configuration.validateExecutable()
        } catch {
            throw fail(PreprocessorError(.executableUnavailable(error)))
        }

        let environment = PreprocessorEnvironment(documentURL: documentURL)
        let session: PreprocessorSession
        do {
            session = try PreprocessorSession(limits: limits)
        } catch {
            throw fail(error)
        }
        let threadName = "peep.\(kind.identifier)"
        let outcome: PreprocessorSession.Outcome?
        do {
            outcome = try await withTaskCancellationHandler {
                try await Self.onDedicatedThread(named: threadName, priority: Task.currentPriority) {
                    () throws(PreprocessorError) -> PreprocessorSession.Outcome? in
                    defer { session.finish() }
                    if session.isCancelled { return nil }
                    let process = try PreprocessorProcess.launch(
                        executable: configuration.executablePath,
                        arguments: configuration.arguments,
                        environment: environment
                    )
                    return session.drive(process, input: Array(input))
                }
            } onCancel: {
                session.cancel()
            }
        } catch let error as PreprocessorError {
            throw fail(error)
        }
        guard let outcome, outcome.stop != .cancelled else { throw CancellationError() }
        do throws(PreprocessorError) {
            return try Self.result(of: outcome, limits: limits, kind: kind)
        } catch {
            throw fail(error)
        }
    }

    /// `error` attributed to this program, logged.
    private func fail(_ error: PreprocessorError) -> PreprocessorError {
        let error = error.attributed(to: kind)
        let (noun, path, message) = (kind.noun, configuration.executablePath, error.message)
        logger.error("Custom \(noun, privacy: .public) \(path) failed: \(message, privacy: .public)")
        return error
    }

    /// Turns a finished run into text or the error it earned.
    static func result(
        of outcome: PreprocessorSession.Outcome, limits: PreprocessorLimits, kind: CustomProgramKind = .preprocessor
    ) throws(PreprocessorError) -> String {
        // stderr is for the reader to look at, so it's decoded leniently (U+FFFD for bad bytes).
        // swiftlint:disable:next optional_data_string_conversion
        let errorTail = String(decoding: outcome.errorTail, as: UTF8.self)
        func failure(_ reason: PreprocessorError.Reason) -> PreprocessorError {
            PreprocessorError(reason, standardError: errorTail, kind: kind)
        }
        switch outcome.stop {
        case .timedOut: throw failure(.timedOut(limits.timeout))
        case .outputTooLarge: throw failure(.outputTooLarge(limit: limits.maximumOutputBytes))
        case .cancelled, nil: break
        }
        let signal = outcome.status & 0x7F
        if signal != 0 { throw failure(.signaled(signal)) }
        let status = (outcome.status >> 8) & 0xFF
        if status != 0 { throw failure(.exited(status: status)) }
        if outcome.output.contains(0) { throw failure(.outputContainsNUL) }
        guard let text = String(validating: outcome.output, as: UTF8.self) else { throw failure(.outputNotUTF8) }
        return text
    }

    /// Runs `body` on a new thread named `name` at a quality of service matching `priority`, and resumes
    /// with its result.
    private static func onDedicatedThread<Value: Sendable>(
        named name: String,
        priority: TaskPriority,
        _ body: @escaping @Sendable () throws(PreprocessorError) -> Value
    ) async throws(PreprocessorError) -> Value {
        let result: Result<Value, PreprocessorError> = await withCheckedContinuation { continuation in
            let thread = Thread {
                continuation.resume(returning: Result { () throws(PreprocessorError) in try body() })
            }
            thread.name = name
            thread.qualityOfService = qualityOfService(for: priority)
            thread.start()
        }
        return try result.get()
    }

    private static func qualityOfService(for priority: TaskPriority) -> QualityOfService {
        if priority >= .userInitiated { return .userInitiated }
        if priority >= .medium { return .default }
        if priority >= .utility { return .utility }
        return .background
    }
}
