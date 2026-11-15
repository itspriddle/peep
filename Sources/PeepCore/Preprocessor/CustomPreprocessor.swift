import Foundation

/// Runs the reader's own executable on a document before rendering (#56).
///
/// The contract (VISION, security model): the document's bytes on stdin, Markdown as UTF-8 on
/// stdout, exit status 0 for success. The executable gets `configuration.arguments` as its
/// argv (no shell), a minimal environment with the document's path in `PEEP_DOCUMENT_PATH`,
/// and the document's folder as its working directory (`PreprocessorEnvironment`). Each run
/// is bounded by `configuration.limits`; a script that hangs, floods output, crashes, or
/// leaves children behind yields a `PreprocessorError` (or `CancellationError`), never a
/// hang, and every process it started in its process group is killed and reaped.
///
/// Opting in is the caller's job: nothing in PeepCore runs a preprocessor unless handed one.
public struct CustomPreprocessor: Sendable {
    public let configuration: PreprocessorConfiguration

    public init(configuration: PreprocessorConfiguration) {
        self.configuration = configuration
    }

    /// Runs the preprocessor on `input` and returns its output.
    ///
    /// The process runs and its pipes are serviced on a dedicated thread, so this never blocks
    /// the cooperative pool. Cancelling the task stops the process group (`SIGTERM`, then
    /// `SIGKILL` after the grace period) and throws `CancellationError` once it is reaped.
    ///
    /// - Parameter documentURL: the document's file, for the environment and working
    ///   directory; `nil` for input without a file.
    public func run(input: Data, documentURL: URL?) async throws -> String {
        try await CustomProgramRunner(configuration: configuration, kind: .preprocessor)
            .run(input: input, documentURL: documentURL)
    }
}
