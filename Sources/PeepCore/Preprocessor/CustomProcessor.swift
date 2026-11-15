import Foundation

/// Runs the reader's own Markdown renderer in place of Peep's (#106): pandoc, markdown-it,
/// comrak, or any program that reads Markdown on stdin and writes HTML on stdout.
///
/// The contract (VISION, security model) is the preprocessor's (`CustomPreprocessor`): the
/// same argv, environment, working directory, limits, and failure handling. The input is the
/// Markdown **body** (frontmatter already removed by the pipeline) and the output is an HTML
/// fragment, which the pipeline always sanitizes
/// (`HTMLRenderer.render(processedHTML:of:)`, `HTMLSanitizerMode.processorOutput`).
///
/// Opting in is the caller's job: nothing in PeepCore runs a processor unless handed one.
public struct CustomProcessor: Sendable {
    public let configuration: PreprocessorConfiguration

    public init(configuration: PreprocessorConfiguration) {
        self.configuration = configuration
    }

    /// Runs the processor on `input` and returns the HTML it wrote. Errors are
    /// `PreprocessorError`s whose `kind` is `.processor`; cancellation works as in
    /// `CustomPreprocessor.run(input:documentURL:)`.
    public func run(input: Data, documentURL: URL?) async throws -> String {
        try await CustomProgramRunner(configuration: configuration, kind: .processor)
            .run(input: input, documentURL: documentURL)
    }

    /// This processor for one document, as the pipeline's `SourceProcessor`.
    public func `for`(documentURL: URL?) -> DocumentProcessor {
        DocumentProcessor(processor: self, documentURL: documentURL)
    }
}

/// A `CustomProcessor` bound to the document it runs on. The body is sent as UTF-8.
public struct DocumentProcessor: SourceProcessor {
    public let processor: CustomProcessor
    public let documentURL: URL?

    public func process(_ body: String) async throws -> String {
        try await processor.run(input: Data(body.utf8), documentURL: documentURL)
    }
}
