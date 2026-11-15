import Foundation
import PeepCore

extension DocumentContent {
    /// Renders `source`, the text of the file at `url` (nil for standard input, #68: titled
    /// "Standard Input" when it has no title of its own, with no allowed root, so relative
    /// images and page links resolve to nothing), with `preferences`: through the custom
    /// preprocessor first when `preferences.customPreprocessor` is set (#57), then the rest of
    /// the pipeline, with the custom processor in place of Peep's renderer when
    /// `preferences.customProcessor` is set (#106). The single render used by opening,
    /// reverting, live reload, and Settings changes (`MarkdownDocument.renderContent`). Runs off
    /// the main actor.
    ///
    /// A failing program (an executable that went away, a timeout, a crash, a non-zero exit,
    /// ...) is not an error here: a failed preprocessor leaves `source` unprocessed, with
    /// `preprocessorError` set, and a failed processor leaves the body to Peep's renderer, with
    /// `processorError` set; the window shows a bar for each. The only error is
    /// `CancellationError`, when the task is cancelled during a run (a newer render, or the
    /// document closed); the runner has then stopped the script's process group.
    ///
    /// The file was already decoded as UTF-8 (`source(from:)`), so the preprocessor gets exactly
    /// the file's bytes, and the processor the body after the frontmatter. Standard input's
    /// programs run with no document path, in `/`, as in the CLI.
    static func rendering(
        _ source: String, of url: URL?, preferences: MarkdownPreferences
    ) async throws -> DocumentContent {
        let fallbackTitle = url?.lastPathComponent ?? MarkdownDocument.standardInputName
        let linkRoot = linkRoot(forDocumentAt: url)
        guard preferences.customPreprocessor != nil || preferences.customProcessor != nil else {
            return DocumentContent(
                source: source, fallbackTitle: fallbackTitle, linkRoot: linkRoot, preferences: preferences,
                documentURL: url)
        }

        var renderedSource = source
        var preprocessorError: PreprocessorError?
        if let preference = preferences.customPreprocessor {
            do {
                renderedSource = try await run(.preprocessor, preference, on: source, documentURL: url)
            } catch let error as PreprocessorError {
                preprocessorError = error
            }
        }

        var processedHTML: String?
        var processorError: PreprocessorError?
        if let preference = preferences.customProcessor {
            try Task.checkCancellation()
            let options = renderOptions(preferences: preferences, linkRoot: linkRoot)
            let body = HTMLRenderer(options: options, highlighter: nil).prepare(renderedSource).body
            do {
                processedHTML = try await run(.processor, preference, on: body, documentURL: url)
            } catch let error as PreprocessorError {
                processorError = error
            }
        }

        try Task.checkCancellation()
        return DocumentContent(
            source: source, renderedSource: renderedSource, preprocessorError: preprocessorError,
            processedHTML: processedHTML, processorError: processorError, fallbackTitle: fallbackTitle,
            linkRoot: linkRoot, preferences: preferences, documentURL: url)
    }

    /// One custom program's output for `input`. Throws a `PreprocessorError` (an unusable
    /// executable becomes `.executableUnavailable`) or `CancellationError`.
    private static func run(
        _ kind: CustomProgramKind, _ preference: CustomProgramPreference, on input: String, documentURL: URL?
    ) async throws -> String {
        let configuration: PreprocessorConfiguration
        do throws(PreprocessorExecutableError) {
            configuration = try PreprocessorConfiguration(
                executablePath: preference.executablePath, arguments: preference.arguments)
        } catch {
            throw PreprocessorError(.executableUnavailable(error), kind: kind)
        }
        let data = Data(input.utf8)
        return switch kind {
        case .preprocessor:
            try await CustomPreprocessor(configuration: configuration).run(input: data, documentURL: documentURL)
        case .processor:
            try await CustomProcessor(configuration: configuration).run(input: data, documentURL: documentURL)
        }
    }
}
