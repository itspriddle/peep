/// The render pipeline's alternative to stages 4-6 (#106): an external renderer that turns the
/// Markdown body into an HTML fragment (`CustomProcessor` conforms).
///
/// It gets the body after frontmatter extraction and document overrides
/// (`HTMLRenderer.prepare(_:)`), and its output goes through `HTMLRenderer.render(processedHTML:of:)`,
/// which sanitizes it and collects headings from it. Flavors, the built-in transforms (alerts,
/// wiki links, emoji), highlighting, and `data-source-line` belong to the built-in renderer and
/// don't apply.
public protocol SourceProcessor: Sendable {
    /// The HTML fragment for `body`. Throws when the processor fails; the caller decides what to
    /// show.
    func process(_ body: String) async throws -> String
}

extension HTMLRenderer {
    /// The whole pipeline with a processor: `source` through `preprocessor` (stage 1, if any),
    /// frontmatter and overrides, then `processor` in place of the built-in renderer. Errors are
    /// the programs'; cancellation is checked after each, so a newer render can drop this one.
    public func render(
        _ source: String, preprocessor: (any SourcePreprocessor)?, processor: any SourceProcessor
    ) async throws -> RenderedDocument {
        var markdown = source
        if let preprocessor {
            markdown = try await preprocessor.preprocess(source)
            try Task.checkCancellation()
        }
        let prepared = prepare(markdown)
        let html = try await processor.process(prepared.body)
        try Task.checkCancellation()
        return render(processedHTML: html, of: prepared)
    }
}
