extension MarkdownNode {
    /// `self` with each code block replaced by what `rewrite` returns for it (`nil` keeps the
    /// block as is), for the render-time code block passes (`CodeHighlighting`).
    /// Walks block containers only (code blocks never appear inside
    /// inlines), in document order, with an explicit stack so deep trees can't overflow it, and
    /// rebuilds only the containers that changed.
    func rewritingCodeBlocks(_ rewrite: (CodeBlock) -> CodeBlock?) -> MarkdownNode {
        if case .codeBlock(let block) = kind {
            guard let rewritten = rewrite(block) else {
                return self
            }
            var node = self
            node.kind = .codeBlock(rewritten)
            return node
        }
        var stack = [CodeBlockFrame(self)]
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
            switch child.kind {
            case .codeBlock(let block):
                if let rewritten = rewrite(block) {
                    var node = child
                    node.kind = .codeBlock(rewritten)
                    stack[top].children.append(node)
                    stack[top].changed = true
                } else {
                    stack[top].children.append(child)
                }
            case let kind where kind.isBlockContainer:
                stack.append(CodeBlockFrame(child))
            default:
                stack[top].children.append(child)
            }
        }
        return self
    }
}

private struct CodeBlockFrame {
    var node: MarkdownNode
    var nextChild = 0
    var children: [MarkdownNode] = []
    var changed = false

    init(_ node: MarkdownNode) {
        self.node = node
    }
}
