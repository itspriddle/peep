import Foundation
import PeepCore

/// What `--preprocessor` and `--processor` share (#66, #106): the program's configuration from
/// a path the user typed, the run (cancelled by Ctrl-C when `CLIEnvironment.cancelsOnInterrupt`),
/// and how a failure is reported.
enum CustomProgramCommand {
    /// A program named on the command line: which one, its path as typed, and its arguments.
    struct Program: Sendable {
        let kind: CustomProgramKind
        let executable: String
        let arguments: [String]
    }

    /// Runs `program` (its path relative to the working directory) on `input`, for `document`
    /// (its path and folder for the environment, its name for messages). Any failure is
    /// `ExitStatus.software` with the reason and the program's stderr tail; a cancelled run is
    /// `ExitStatus.interrupted`.
    static func run(
        _ program: Program, input: String, for document: InputDocument, in environment: CLIEnvironment
    ) async throws(CLIError) -> String {
        let kind = program.kind
        let subject = document.source.displayName
        let documentURL = document.source.url
        let configuration: PreprocessorConfiguration
        do throws(PreprocessorExecutableError) {
            configuration = try PreprocessorConfiguration(
                executablePath: absolutePath(program.executable),
                arguments: program.arguments,
                limits: environment.preprocessorLimits)
        } catch {
            throw failure(subject, PreprocessorError(.executableUnavailable(error), kind: kind))
        }

        let data = Data(input.utf8)
        let run: @Sendable () async throws -> String = {
            switch kind {
            case .preprocessor:
                try await CustomPreprocessor(configuration: configuration).run(input: data, documentURL: documentURL)
            case .processor:
                try await CustomProcessor(configuration: configuration).run(input: data, documentURL: documentURL)
            }
        }
        do {
            return environment.cancelsOnInterrupt ? try await InterruptCancellation.run(run) : try await run()
        } catch let error as PreprocessorError {
            throw failure(subject, error)
        } catch {
            // Cancelled. With live signal handling the signal has already ended the process.
            throw CLIError("\(subject): the \(kind.noun) was interrupted", status: ExitStatus.interrupted)
        }
    }

    /// `path` made absolute against the working directory. It's a path, never a command name.
    static func absolutePath(_ path: String) -> String {
        URL(fileURLWithPath: path).absoluteURL.path(percentEncoded: false)
    }

    /// `peep: <input>: <reason>`, then the program's stderr tail on the following lines, with
    /// control characters other than tabs and newlines escaped (it may echo the document).
    static func failure(_ subject: String, _ error: PreprocessorError) -> CLIError {
        var message = "\(subject): \(error.message)"
        let tail = error.standardError.trimmingCharacters(in: .newlines)
        if !tail.isEmpty {
            let lines = tail.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map { line in
                line.split(separator: "\t", omittingEmptySubsequences: false)
                    .map { RenderFlagOptions.terminalSafe(String($0)) }
                    .joined(separator: "\t")
            }
            message += "\n" + lines.joined(separator: "\n")
        }
        return CLIError(message, status: ExitStatus.software)
    }
}
