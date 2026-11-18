/// The render-time highlighting pass: runs a `SyntaxHighlighter` over a tree's fenced code
/// blocks and stores validated markup on each block for `HTMLRenderer` to write.
///
/// - Only blocks whose info string names a language (its first word) are highlighted; the
///   highlighter resolves the name and returns `nil` for languages it doesn't know.
/// - Blocks larger than `maximumBlockBytes` are skipped, and at most `documentBudgetBytes` of
///   code is highlighted per document: a block that doesn't fit in what's left of the budget is
///   skipped (a later, smaller one may still fit). Each call is charged at least
///   `minimumChargeBytes`, so many tiny blocks can't run up unbounded calls. JavaScriptCore has
///   no public execution time limit, so these caps bound the work instead (highlight.js runs at
///   roughly 1 MB/s, so the budget is about 200 ms of highlighting in the worst case).
/// - Output is accepted only through `HighlightValidator`; rejected output, unknown languages,
///   and skipped blocks render as plain escaped code.
struct CodeHighlighting {
    static let maximumBlockBytes = 128 * 1024
    static let documentBudgetBytes = 256 * 1024
    static let minimumChargeBytes = 512

    let highlighter: any SyntaxHighlighter
    private var remainingBudget = Self.documentBudgetBytes

    init(highlighter: any SyntaxHighlighter) {
        self.highlighter = highlighter
    }

    /// Validated highlighted markup for `block`, or `nil` to render it plain.
    mutating func highlight(_ block: CodeBlock) -> String? {
        guard let language = block.language else {
            return nil
        }
        let size = block.literal.utf8.count
        let charge = max(size, Self.minimumChargeBytes)
        guard size <= Self.maximumBlockBytes, charge <= remainingBudget else {
            return nil
        }
        remainingBudget -= charge
        guard let html = highlighter.highlight(block.literal, language: language) else {
            return nil
        }
        return HighlightValidator.validated(html, source: block.literal)
    }

    /// Returns `root` with `CodeBlock.highlightedHTML` set on every block that highlights.
    /// Blocks drawn as diagrams (`CodeBlock.diagramSVG`, `DiagramRendering`, which runs first)
    /// are left alone and cost nothing.
    mutating func apply(to root: MarkdownNode) -> MarkdownNode {
        root.rewritingCodeBlocks { block in
            guard block.diagramSVG == nil, let html = highlight(block) else {
                return nil
            }
            var block = block
            block.highlightedHTML = html
            return block
        }
    }
}
