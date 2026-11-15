import Foundation

/// What Quick Look's thumbnail shows: the start of a document as plain text blocks, with the
/// theme's background. The thumbnail extension draws it natively (no web view), so it's cheap
/// enough for a Finder folder full of files.
public struct QuickLookThumbnail: Sendable, Equatable {
    /// One block of the document's start, as plain text.
    public enum Block: Sendable, Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case listItem(String)
        case quote(String)
        case code(String)
        case rule
    }

    /// The most blocks a thumbnail keeps; a thumbnail shows only the first few anyway.
    public static let maximumBlocks = 16
    /// The longest text a block keeps.
    public static let maximumBlockLength = 400
    /// The most of a file a thumbnail reads.
    public static let maximumSourceBytes = 256 * 1024

    public var blocks: [Block]
    /// The page background of the theme the preview would use.
    public var background: ThemeBackground

    public init(blocks: [Block], background: ThemeBackground) {
        self.blocks = blocks
        self.background = background
    }

    /// The thumbnail for the file `data`, or `nil` when it isn't UTF-8. Only the first
    /// `maximumSourceBytes` are read; frontmatter is never shown, but its `peep.theme` and
    /// `peep.flavor` apply as they do in the preview.
    public static func make(data: Data, configuration: QuickLookConfiguration) -> QuickLookThumbnail? {
        guard let source = try? QuickLookPreview.source(from: data, maximumBytes: maximumSourceBytes) else {
            return nil
        }
        var options = QuickLookPreview.renderOptions(for: configuration)
        options.frontmatterDisplay = .hidden
        options.highlighting = false
        let renderer = HTMLRenderer(options: options, highlighter: nil, wikiLinkResolver: nil)
        let prepared = renderer.prepare(source.markdown)
        let tree = MarkdownParser(extensions: prepared.options.flavor.extensions).parse(prepared.body)
        let document = HTMLRenderer(options: prepared.options, highlighter: nil).transformed(tree)

        var blocks: [Block] = []
        if let title = prepared.frontmatter?.title, !title.isEmpty {
            blocks.append(.heading(level: 1, text: clipped(title)))
        }
        collect(document.children, into: &blocks)

        let registry = configuration.themeRegistry
        let themeID = prepared.overrides.theme.flatMap { registry.contains(id: $0) ? $0 : nil } ?? configuration.themeID
        return QuickLookThumbnail(
            blocks: Array(blocks.prefix(maximumBlocks)), background: registry.theme(id: themeID).background)
    }

    private static func collect(_ nodes: [MarkdownNode], into blocks: inout [Block]) {
        for node in nodes where blocks.count < maximumBlocks {
            switch node.kind {
            case .heading(let level):
                append(.heading(level: level, text: plainText(of: node)), to: &blocks)
            case .paragraph:
                append(.paragraph(plainText(of: node)), to: &blocks)
            case .list:
                for item in node.children where blocks.count < maximumBlocks {
                    let text = item.children.first.map(plainText(of:)) ?? ""
                    append(.listItem(text), to: &blocks)
                }
            case .blockQuote, .alert:
                append(.quote(node.children.map(plainText(of:)).joined(separator: " ")), to: &blocks)
            case .codeBlock(let code):
                let lines = code.literal.split(separator: "\n", omittingEmptySubsequences: false).prefix(12)
                append(.code(lines.joined(separator: "\n")), to: &blocks)
            case .thematicBreak:
                blocks.append(.rule)
            default:
                break
            }
        }
    }

    private static func append(_ block: Block, to blocks: inout [Block]) {
        switch block {
        case .heading(let level, let text) where !text.isEmpty:
            blocks.append(.heading(level: level, text: clipped(text)))
        case .paragraph(let text) where !text.isEmpty:
            blocks.append(.paragraph(clipped(text)))
        case .listItem(let text) where !text.isEmpty:
            blocks.append(.listItem(clipped(text)))
        case .quote(let text) where !text.isEmpty:
            blocks.append(.quote(clipped(text)))
        case .code(let text) where !text.isEmpty:
            blocks.append(.code(clipped(text)))
        default:
            break
        }
    }

    private static func clipped(_ text: String) -> String {
        text.count > maximumBlockLength ? String(text.prefix(maximumBlockLength)) + "…" : text
    }

    /// The text a reader sees in `node`: text, code spans, emoji; raw HTML and images left out.
    static func plainText(of node: MarkdownNode) -> String {
        var text = ""
        var stack = node.children.reversed() as [MarkdownNode]
        while let current = stack.popLast() {
            switch current.kind {
            case .text(let literal), .code(let literal), .emoji(_, let literal):
                text += literal
            case .softBreak, .lineBreak:
                text += " "
            case .image, .htmlInline, .htmlBlock:
                break
            default:
                stack.append(contentsOf: current.children.reversed())
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
