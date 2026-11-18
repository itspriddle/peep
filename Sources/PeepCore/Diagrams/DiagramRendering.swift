/// The render-time diagram pass (M7, `RenderOptions.diagrams`): draws fenced code blocks whose
/// language is a `DiagramKind` as static SVG and stores it on the block
/// (`CodeBlock.diagramSVG`) for `HTMLRenderer` to write in a `<figure>`.
///
/// - Pure Swift, no JavaScript and no remote loads, so the viewer, `peep --html`, Copy as HTML,
///   and Quick Look all get the same markup.
/// - Every byte of the SVG comes from `SVGWriter`: fixed element and attribute names and finite
///   formatted numbers. No input string is ever written as markup.
/// - Caps: a block over `maximumBlockBytes` isn't read, and a document draws at most
///   `documentCoordinateBudget` coordinates: a block that doesn't fit in what's left is shown as
///   code (a later, smaller one may still fit). Over a cap, unreadable input, or nothing to
///   draw, the block renders as the plain code block it was.
/// - Runs before `CodeHighlighting`, which skips the blocks drawn here.
struct DiagramRendering {
    static let maximumBlockBytes = 1024 * 1024
    static let documentCoordinateBudget = 200_000

    private var budget: DiagramBudget

    init(coordinateBudget: Int = Self.documentCoordinateBudget) {
        budget = DiagramBudget(coordinates: coordinateBudget)
    }

    /// Coordinates this document may still draw.
    var remainingCoordinates: Int {
        budget.coordinates
    }

    /// The SVG for `block`, or `nil` to render it as code.
    mutating func diagram(for block: CodeBlock) -> String? {
        guard block.isFenced, let kind = DiagramKind(language: block.language),
            block.literal.utf8.count <= Self.maximumBlockBytes
        else {
            return nil
        }
        return kind.render(block.literal, budget: &budget)
    }

    /// Returns `root` with `CodeBlock.diagramSVG` set on every block drawn as a diagram.
    mutating func apply(to root: MarkdownNode) -> MarkdownNode {
        root.rewritingCodeBlocks { block in
            guard let svg = diagram(for: block) else {
                return nil
            }
            var block = block
            block.diagramSVG = svg
            return block
        }
    }
}
