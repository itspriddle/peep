import Foundation
import Testing

@testable import PeepCore

@Suite("Quick Look")
struct QuickLookTests {
    private static let safeCSS = """
        /* peep-theme
           name: Solarized
           background: #fdf6e3
        */
        body { color: #657b83; }
        """

    private func page(_ markdown: String, _ configuration: QuickLookConfiguration = .default) throws -> String {
        try QuickLookPreview.html(
            data: Data(markdown.utf8), fileName: "README.md", configuration: configuration, highlighter: nil)
    }

    // MARK: Configuration

    @Test("the configuration round-trips through its encoding")
    func roundTrip() throws {
        let configuration = QuickLookConfiguration(
            themeID: "custom:solarized.css",
            customTheme: QuickLookCustomTheme(fileName: "solarized.css", css: Self.safeCSS), flavorID: "commonmark",
            frontmatterDisplay: .table, builtInPreprocessors: [.wikiLinks])
        let data = try #require(configuration.encoded())
        #expect(QuickLookConfiguration(data: data) == configuration)
    }

    @Test(
        "missing, malformed, or oversized data is the default",
        arguments: [
            nil, Data(), Data("not json".utf8), Data(#"{"themeID": 3}"#.utf8),
            Data(repeating: 0x20, count: QuickLookConfiguration.maximumEncodedSize + 1),
        ])
    func malformed(data: Data?) {
        #expect(QuickLookConfiguration(data: data) == .default)
    }

    @Test(
        "the App Group identifier needs a team prefix",
        arguments: [
            ("ABCDE12345.now.peep", "ABCDE12345.now.peep"), ("now.peep", nil), (".now.peep", nil),
            ("abcde12345.now.peep", nil), ("ABCDE1234.now.peep", nil), ("ABCDE12345.now.peep.x", nil),
            ("ABCDE/2345.now.peep", nil),
        ] as [(String, String?)])
    func appGroup(value: String, expected: String?) {
        #expect(QuickLookConfiguration.appGroupIdentifier(infoValue: value) == expected)
        #expect(QuickLookConfiguration.appGroupIdentifier(infoValue: nil) == nil)
        #expect(QuickLookConfiguration.appGroupIdentifier(infoValue: 3) == nil)
    }

    @Test("unknown values fall back")
    func unknownValues() throws {
        let data = Data(
            #"{"flavorID":"nope","frontmatterDisplay":"loud","builtInPreprocessors":["emoji","x","wikiLinks"]}"#.utf8)
        let configuration = QuickLookConfiguration(data: data)
        #expect(configuration.flavor == .gfm)
        #expect(configuration.frontmatter == .hidden)
        #expect(configuration.preprocessors == [.wikiLinks])
    }

    @Test("a custom theme is registered only when it is the picked theme and passes the checks")
    func customThemeChecks() {
        let good = QuickLookCustomTheme(fileName: "solarized.css", css: Self.safeCSS)
        let picked = QuickLookConfiguration(themeID: "custom:solarized.css", customTheme: good)
        #expect(picked.themeRegistry.contains(id: "custom:solarized.css"))

        let notPicked = QuickLookConfiguration(themeID: "serif", customTheme: good)
        #expect(!notPicked.themeRegistry.contains(id: "custom:solarized.css"))

        let remote = QuickLookCustomTheme(
            fileName: "evil.css", css: "body { background: url(https://example.com/track.png); }")
        #expect(remote.theme == nil)
        let traversal = QuickLookCustomTheme(fileName: "../evil.css", css: Self.safeCSS)
        #expect(traversal.theme == nil)
        let huge = QuickLookCustomTheme(
            fileName: "big.css", css: String(repeating: " ", count: CustomThemeFolder.maximumFileSize + 1))
        #expect(huge.theme == nil)
    }

    // MARK: Preview

    @Test("the page uses the Quick Look CSP: no scripts, data: images only")
    func contentSecurityPolicy() throws {
        let html = try page("# Hello")
        #expect(html.contains(ContentSecurityPolicy.quickLook.header))
        #expect(ContentSecurityPolicy.quickLook.header.contains("default-src 'none'"))
        #expect(ContentSecurityPolicy.quickLook.header.contains("img-src data:;"))
    }

    @Test("local and remote images become placeholders; data: images stay")
    func images() throws {
        let html = try page(
            """
            ![Logo](img/logo.png) ![Badge](https://img.shields.io/b.svg) ![Dot](data:image/gif;base64,R0lGODlhAQABAAAAACw=)

            <img src="../shot.png" alt="Shot"> <img src="/root.png">
            """)
        #expect(!html.contains("src=\"img/logo.png\""))
        #expect(!html.contains("src=\"https:"))
        #expect(!html.contains("src=\"../shot.png\""))
        #expect(!html.contains("src=\"/root.png\""))
        #expect(html.contains("aria-label=\"Image not shown: Logo (logo.png)\""))
        #expect(html.contains("aria-label=\"Image not shown: Shot (shot.png)\""))
        #expect(html.contains("aria-label=\"Blocked remote image: Badge (img.shields.io)\""))
        #expect(html.contains("src=\"data:image/gif;base64,"))
    }

    @Test("raw HTML is sanitized")
    func sanitized() throws {
        let html = try page("<script>alert(1)</script><a href=\"javascript:alert(1)\" onclick=\"x()\">x</a>")
        #expect(!html.contains("<script>alert"))
        #expect(!html.contains("javascript:"))
        #expect(!html.contains("onclick"))
    }

    @Test("render options fix the safety settings")
    func safetySettings() {
        let options = QuickLookPreview.renderOptions(
            for: QuickLookConfiguration(flavorID: "commonmark", frontmatterDisplay: .table))
        #expect(options.flavor == .commonmark)
        #expect(options.frontmatterDisplay == .table)
        #expect(options.remoteImages == .blockAll)
        #expect(options.sanitize)
        #expect(options.linkRoot == nil)
    }

    @Test("wiki links render as missing pages: no resolver reads the folder")
    func wikiLinks() throws {
        let html = try page("[[Other Page]]", QuickLookConfiguration(builtInPreprocessors: [.wikiLinks]))
        #expect(html.contains("Other Page"))
        #expect(!html.contains("href=\"Other"))
    }

    @Test("the theme: the document's peep.theme, then the configuration's, then GitHub")
    func themeOrder() throws {
        let serif = QuickLookConfiguration(themeID: "serif")
        #expect(try page("# A", serif).contains(Theme.serif.layerCSS))
        #expect(try page("---\npeep:\n  theme: document\n---\n# A", serif).contains(Theme.document.layerCSS))
        #expect(try page("---\npeep:\n  theme: custom:gone.css\n---\n# A", serif).contains(Theme.serif.layerCSS))
        #expect(try page("# A", QuickLookConfiguration(themeID: "nope")).contains(Theme.github.layerCSS))
    }

    @Test("a custom theme that fails the checks falls back to GitHub")
    func rejectedCustomTheme() throws {
        let configuration = QuickLookConfiguration(
            themeID: "custom:evil.css",
            customTheme: QuickLookCustomTheme(fileName: "evil.css", css: "@import url(https://example.com/x.css);"))
        let html = try page("# A", configuration)
        #expect(html.contains(Theme.github.layerCSS))
        #expect(!html.contains("example.com"))
    }

    @Test("a custom theme that passes is used")
    func customTheme() throws {
        let configuration = QuickLookConfiguration(
            themeID: "custom:solarized.css",
            customTheme: QuickLookCustomTheme(fileName: "solarized.css", css: Self.safeCSS))
        #expect(try page("# A", configuration).contains("color: #657b83"))
    }

    @Test("a long file is cut after a line break, with a note")
    func truncation() throws {
        let line = "Line with é accent\n"
        let data = Data(String(repeating: line, count: 10).utf8)
        let source = try QuickLookPreview.source(from: data, maximumBytes: line.utf8.count * 3 + 5)
        #expect(source.isTruncated)
        #expect(source.markdown == String(repeating: line, count: 3))

        let whole = try QuickLookPreview.source(from: data)
        #expect(!whole.isTruncated)
    }

    @Test("bytes that aren't UTF-8 fail, so Quick Look shows its own preview")
    func notUTF8() {
        #expect(throws: QuickLookPreview.Failure.notUTF8) {
            try QuickLookPreview.source(from: Data([0x23, 0x20, 0xFF, 0xFE]))
        }
    }

    @Test("the page title is the document's, else the file name")
    func title() throws {
        #expect(try page("# Hello").contains("<title>Hello</title>"))
        #expect(try page("text").contains("<title>README.md</title>"))
    }

    // MARK: Thumbnail

    @Test("the thumbnail keeps the start of the document as plain blocks")
    func thumbnailBlocks() throws {
        let markdown = """
            ---
            title: The Title
            peep:
              theme: serif
            ---
            # Heading *one*

            Some `code` and ![img](a.png) text.

            - first
            - second

            > quoted

            ```swift
            let x = 1
            ```

            ---
            """
        let thumbnail = try #require(QuickLookThumbnail.make(data: Data(markdown.utf8), configuration: .default))
        #expect(
            thumbnail.blocks == [
                .heading(level: 1, text: "The Title"),
                .heading(level: 1, text: "Heading one"),
                .paragraph("Some code and  text."),
                .listItem("first"),
                .listItem("second"),
                .quote("quoted"),
                .code("let x = 1\n"),
                .rule,
            ])
        #expect(thumbnail.background == Theme.serif.background)
    }

    @Test("the thumbnail keeps at most maximumBlocks blocks")
    func thumbnailCap() throws {
        let markdown = (1...50).map { "Paragraph \($0)\n" }.joined(separator: "\n")
        let thumbnail = try #require(QuickLookThumbnail.make(data: Data(markdown.utf8), configuration: .default))
        #expect(thumbnail.blocks.count == QuickLookThumbnail.maximumBlocks)
    }

    @Test("no thumbnail for bytes that aren't UTF-8")
    func thumbnailNotUTF8() {
        #expect(QuickLookThumbnail.make(data: Data([0xFF, 0xFE]), configuration: .default) == nil)
    }
}
