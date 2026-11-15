import ArgumentParser
import Foundation
import PeepCore

/// The custom processor on request (#106): another Markdown renderer in place of Peep's.
/// Headless output never runs a program unless `--processor` names one; the app's Settings >
/// Markdown processor doesn't apply here.
///
/// The run is PeepCore's `CustomProcessor`, with the preprocessor's contract and limits: the
/// Markdown body (after the frontmatter) on stdin, an HTML fragment on stdout, which Peep
/// sanitizes and wraps in its page. It runs after `--preprocessor`, when both are given.
public struct ProcessorOptions: ParsableArguments, Sendable {
    @Option(
        name: .customLong("processor"),
        help: ArgumentHelp(
            "Render with the program at PATH (a file, not a command name) instead of Peep: "
                + "the Markdown body on its stdin, HTML on its stdout.",
            valueName: "PATH"),
        completion: .file())
    public var executable: String?

    @Option(
        name: .customLong("processor-arg"),
        parsing: .unconditionalSingleValue,
        help: ArgumentHelp(
            "An argument for the --processor program, passed as is (repeatable).", valueName: "ARG"))
    public var arguments: [String] = []

    public init() {}

    /// Whether a processor flag was given. They change HTML output only, so without `--html`,
    /// `--fragment`, or `--output` they are a usage error (`PeepCommand.validate()`).
    var isSet: Bool { executable != nil || !arguments.isEmpty }

    public func validate() throws {
        if executable == nil, !arguments.isEmpty {
            throw ValidationError("--processor-arg needs --processor.")
        }
        if executable?.isEmpty == true {
            throw ValidationError("--processor needs the path of a program.")
        }
    }

    /// The `SourceProcessor` stand-in for one input: the program's HTML for `body`, or nil
    /// without `--processor`. Failures are reported as `--preprocessor`'s are (`ExitStatus.software`
    /// with the stderr tail); nothing falls back to Peep's renderer.
    func process(_ body: String, of document: InputDocument, in environment: CLIEnvironment) async throws(CLIError)
        -> String?
    {
        guard let executable else { return nil }
        return try await CustomProgramCommand.run(
            CustomProgramCommand.Program(kind: .processor, executable: executable, arguments: arguments),
            input: body, for: document, in: environment)
    }
}
