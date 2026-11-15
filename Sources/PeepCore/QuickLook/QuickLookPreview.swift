import Foundation

/// Quick Look's rendered page: what the preview extension returns as HTML for Quick Look to show.
///
/// It runs the same pipeline as the app with the safety settings fixed, whatever the
/// configuration says: no custom preprocessor or processor (pressing space on a downloaded file
/// must never run a program), no wiki link resolver (page links render as missing, as in
/// `peep --html`), every image but `data:` URLs replaced with a placeholder
/// (`RemoteImagePolicy.blockAll`; the sandbox can't read the folder, and nothing remote loads),
/// raw HTML sanitized, and `ContentSecurityPolicy.quickLook` (no scripts).
public enum QuickLookPreview {
    /// The most of a file Quick Look renders. A longer file renders up to the last line break
    /// before this, with a note at the end.
    public static let maximumSourceBytes = 2 * 1024 * 1024

    /// A file's text as Quick Look renders it.
    public struct Source: Sendable, Equatable {
        public var markdown: String
        /// The file was longer than `maximumSourceBytes` and was cut.
        public var isTruncated: Bool
    }

    /// Why a file can't be previewed; Quick Look then shows its own plain preview.
    public enum Failure: Error, Sendable, Equatable {
        /// The bytes aren't UTF-8 (the app refuses them too).
        case notUTF8
    }

    /// The text of `data`, cut after the last line break within `maximumBytes` when longer. A
    /// line break byte is never part of a multibyte UTF-8 sequence, so the cut stays valid UTF-8.
    public static func source(from data: Data, maximumBytes: Int = maximumSourceBytes) throws(Failure) -> Source {
        var bytes = data
        var isTruncated = false
        if bytes.count > maximumBytes {
            let head = bytes.prefix(maximumBytes)
            let end = head.lastIndex(of: UInt8(ascii: "\n")).map { head.index(after: $0) } ?? head.endIndex
            bytes = Data(head[..<end])
            isTruncated = true
        }
        guard let markdown = String(bytes: bytes, encoding: .utf8) else {
            throw .notUTF8
        }
        return Source(markdown: markdown, isTruncated: isTruncated)
    }

    /// The first `maximumBytes + 1` bytes of the file at `url` (so `source(from:maximumBytes:)`
    /// can tell it was longer), never the whole of a huge file.
    public static func readPrefix(of url: URL, maximumBytes: Int = maximumSourceBytes) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: maximumBytes + 1) ?? Data()
    }

    /// The render options for `configuration`: its flavor, frontmatter display, and built-in
    /// preprocessors, then the fixed safety settings.
    public static func renderOptions(for configuration: QuickLookConfiguration) -> RenderOptions {
        var options = RenderOptions(flavor: configuration.flavor)
        options.frontmatterDisplay = configuration.frontmatter
        options.builtInPreprocessors = configuration.preprocessors
        options.remoteImages = .blockAll
        options.linkRoot = nil
        options.sanitize = true
        return options
    }

    /// The page for the file `data` named `fileName`: themed with the document's `peep.theme`
    /// when the configuration's registry has it, else the configuration's theme.
    public static func html(
        data: Data, fileName: String, configuration: QuickLookConfiguration,
        highlighter: (any SyntaxHighlighter)? = HighlightJSHighlighter.shared
    ) throws(Failure) -> String {
        let source = try source(from: data)
        let renderer = HTMLRenderer(
            options: renderOptions(for: configuration), highlighter: highlighter, wikiLinkResolver: nil)
        let rendered = renderer.render(source.markdown)
        var body = rendered.html
        if source.isTruncated {
            body += truncationNote
        }
        return HTMLDocument(
            title: rendered.title ?? fileName,
            body: body,
            theme: theme(for: rendered, configuration: configuration),
            contentSecurityPolicy: .quickLook
        ).html
    }

    /// The document's `peep.theme` if registered, else `configuration.themeID`, else the default.
    static func theme(for rendered: RenderedDocument, configuration: QuickLookConfiguration) -> Theme {
        let registry = configuration.themeRegistry
        if let id = rendered.overrides.theme, registry.contains(id: id) {
            return registry.theme(id: id)
        }
        return registry.theme(id: configuration.themeID)
    }

    /// Shown after a cut file's text. Constant markup, no document text.
    static let truncationNote =
        "\n<hr />\n<p><em>Quick Look shows the first \(maximumSourceBytes / 1024 / 1024) MB of this file. "
        + "Open it in Peep to see all of it.</em></p>\n"
}
