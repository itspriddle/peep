import ArgumentParser
import Foundation
import PeepCore

/// The custom preprocessor on request (#66). Headless output never runs a program unless
/// `--preprocessor` names one; the app's Settings > Markdown preprocessor doesn't apply here.
///
/// The run is PeepCore's `CustomPreprocessor`, with the app's contract and limits: the input's
/// bytes on stdin, Markdown on stdout, `PEEP_DOCUMENT_PATH` and the document's folder as the
/// working directory for a file (`/` and no path for standard input).
public struct PreprocessorOptions: ParsableArguments, Sendable {
    @Option(
        name: .customLong("preprocessor"),
        help: ArgumentHelp(
            "Run the program at PATH (a file, not a command name) on each input first: "
                + "the document on its stdin, Markdown on its stdout.",
            valueName: "PATH"),
        completion: .file())
    public var executable: String?

    @Option(
        name: .customLong("preprocessor-arg"),
        parsing: .unconditionalSingleValue,
        help: ArgumentHelp(
            "An argument for the --preprocessor program, passed as is (repeatable).", valueName: "ARG"))
    public var arguments: [String] = []

    public init() {}

    /// Whether a preprocessor flag was given. Like the Rendering flags they change HTML output
    /// only, so without `--html`, `--fragment`, or `--output` they are a usage error
    /// (`PeepCommand.validate()`).
    var isSet: Bool { executable != nil || !arguments.isEmpty }

    public func validate() throws {
        if executable == nil, !arguments.isEmpty {
            throw ValidationError("--preprocessor-arg needs --preprocessor.")
        }
        if executable?.isEmpty == true {
            throw ValidationError("--preprocessor needs the path of a program.")
        }
    }

    /// The Markdown to render for `document`: unchanged without `--preprocessor`, else the
    /// program's output. Any failure (the program can't run, exits non-zero, times out, writes
    /// too much or not UTF-8) is `ExitStatus.software`, with the reason and the tail of its
    /// stderr; nothing is rendered unprocessed.
    func preprocess(_ document: InputDocument, in environment: CLIEnvironment) async throws(CLIError) -> String {
        guard let executable else { return document.markdown }
        return try await CustomProgramCommand.run(
            CustomProgramCommand.Program(kind: .preprocessor, executable: executable, arguments: arguments),
            input: document.markdown, for: document, in: environment)
    }
}
