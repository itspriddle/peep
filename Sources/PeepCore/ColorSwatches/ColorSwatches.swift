/// Marks inline code spans that are a color (`` `#0969DA` ``, `` `rgb(9, 105, 218)` ``,
/// `` `hsl(212, 92%, 45%)` ``) so the renderer draws a swatch after them, as GitHub does in
/// issues and comments. An opt-in built-in preprocessor (`MarkdownTransform.colorSwatches`).
///
/// The one transform that reads a `code` node: it only checks whether the span's whole literal
/// is a `SwatchColor` and swaps the node for a `colorCode` node with the same literal and source
/// range. The span's text is never re-parsed into markup, and the swatch color the page sees is
/// re-serialized from bytes (`SwatchColor.hex`). Code blocks and image alt text are left alone.
enum ColorSwatches {
    /// Returns `root` with every color code span replaced by a `colorCode` node.
    static func replace(in root: MarkdownNode) -> MarkdownNode {
        guard descends(into: root) else {
            return marked(root) ?? root
        }
        var stack = [Frame(root)]
        while let top = stack.indices.last {
            guard stack[top].nextChild < stack[top].node.children.count else {
                let frame = stack.removeLast()
                var node = frame.node
                if frame.changed {
                    node.children = frame.children
                }
                guard !stack.isEmpty else {
                    return node
                }
                stack[stack.count - 1].children.append(node)
                stack[stack.count - 1].changed = stack[stack.count - 1].changed || frame.changed
                continue
            }
            let child = stack[top].node.children[stack[top].nextChild]
            stack[top].nextChild += 1
            if let colorCode = marked(child) {
                stack[top].children.append(colorCode)
                stack[top].changed = true
            } else if descends(into: child) {
                stack.append(Frame(child))
            } else {
                stack[top].children.append(child)
            }
        }
        return root
    }

    /// `node` as a `colorCode` node when it is a code span holding exactly a color.
    private static func marked(_ node: MarkdownNode) -> MarkdownNode? {
        guard case .code(let literal) = node.kind, let color = SwatchColor(parsing: literal) else {
            return nil
        }
        return MarkdownNode(.colorCode(literal: literal, color: color), sourceRange: node.sourceRange)
    }

    /// Images keep their alt text plain; leaves have nothing to walk.
    private static func descends(into node: MarkdownNode) -> Bool {
        if case .image = node.kind {
            return false
        }
        return !node.children.isEmpty
    }

    private struct Frame {
        var node: MarkdownNode
        var nextChild = 0
        var children: [MarkdownNode] = []
        var changed = false

        init(_ node: MarkdownNode) {
            self.node = node
            children.reserveCapacity(node.children.count)
        }
    }
}

extension ColorSwatches: MarkdownTreeTransform {
    static func apply(to root: MarkdownNode, context: TransformContext) -> MarkdownNode {
        replace(in: root)
    }
}
