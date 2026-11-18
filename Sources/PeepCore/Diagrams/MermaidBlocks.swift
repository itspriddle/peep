/// Mermaid diagram blocks (#117): fenced code blocks whose language (the info string's first
/// word) is `mermaid`, in any case. PeepCore renders them as ordinary code blocks
/// (`language-mermaid`) everywhere; only the app's viewer draws them, with the vendored mermaid
/// in its own content world. `RenderedDocument.hasMermaidBlocks` tells it whether a page needs
/// mermaid at all, so pages without diagrams never load it.
public enum MermaidBlocks {
    /// The code block language that marks a mermaid diagram (compared case-insensitively).
    public static let language = "mermaid"

    /// Whether `block` is a mermaid diagram.
    public static func isMermaid(_ block: CodeBlock) -> Bool {
        block.language?.lowercased() == language
    }

    /// Whether `root` (a document, or any subtree) has a mermaid block anywhere, including in
    /// block quotes, lists, alerts, and footnotes.
    public static func contains(in root: MarkdownNode) -> Bool {
        var stack = [root]
        while let node = stack.popLast() {
            if case .codeBlock(let block) = node.kind {
                if isMermaid(block) {
                    return true
                }
                continue
            }
            stack.append(contentsOf: node.children)
        }
        return false
    }
}
