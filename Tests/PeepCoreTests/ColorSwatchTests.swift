import Testing

@testable import PeepCore

@Suite("Color swatches")
struct ColorSwatchTests {
    static func render(_ markdown: String, swatches: Bool = true) -> RenderedDocument {
        var options = RenderOptions()
        if swatches {
            options.builtInPreprocessors = [.colorSwatches]
        }
        return HTMLRenderer(options: options).render(markdown)
    }

    static func swatch(_ literal: String, _ hex: String) -> String {
        "<code>\(literal)<span class=\"peep-color-swatch\" style=\"background-color: \(hex)\"></span></code>"
    }

    // MARK: - Parsing (GitHub's rules, checked with `gh api markdown`)

    @Test(
        "accepts GitHub's color forms",
        arguments: [
            ("#0969DA", "#0969da"),
            ("#0969da", "#0969da"),
            ("#FFFFFF", "#ffffff"),
            ("rgb(9, 105, 218)", "#0969da"),
            ("rgb(9,105,218)", "#0969da"),
            ("rgb( 9 ,  105,218 )", "#0969da"),
            ("rgb(9.5, 105, 218)", "#0a69da"),
            ("rgb(300, 0, 1234)", "#ff00ff"),
            ("rgba(9, 105, 218, 0.5)", "#0969da80"),
            ("rgba(9, 105, 218, .5)", "#0969da80"),
            ("rgba(9, 105, 218, 1.5)", "#0969da"),
            ("rgba(9, 105, 218, 0)", "#0969da00"),
            ("hsl(212, 92%, 45%)", "#096cdc"),
            ("hsl(212,92%,45%)", "#096cdc"),
            ("hsl(0, 100%, 50%)", "#ff0000"),
            ("hsl(120, 100%, 25%)", "#008000"),
            ("hsl(240, 100%, 50%)", "#0000ff"),
            ("hsl(480, 100%, 50%)", "#00ff00"),
            ("hsl(0, 0%, 100%)", "#ffffff"),
            ("hsl(212.5, 92.5%, 45%)", "#096add"),
            ("hsl(400, 200%, 45%)", "#e69900"),
        ])
    func accepts(text: String, hex: String) throws {
        let color = try #require(SwatchColor(parsing: text))
        #expect(color.hex == hex)
    }

    @Test(
        "rejects everything else",
        arguments: [
            "", "#", "#fff", "#FFF", "#0969da80", "#0969DZ", "#0969DA;", " #0969DA", "0969DA",
            "RGB(9, 105, 218)", "rgb (9, 105, 218)", "rgb(9 105 218)", "rgb(10%, 20%, 30%)",
            "rgb(9, 105, 218, 0.5)", "rgba(9, 105, 218)", "rgba(9, 105, 218, 50%)", "rgb(-9, 105, 218)",
            "rgb(9., 105, 218)", "rgb(9, , 218)", "rgb(9, 105, 218", "rgb(9, 105, 218))", "rgb(1e3, 0, 0)",
            "hsl(212, 92, 45)", "hsl(212deg, 92%, 45%)", "hsla(212, 92%, 45%, 0.5)", "hsl(212%, 92%, 45%)",
            "color: #0969DA", "#0969DA\" onmouseover=\"x", "rgb(9, 105, 218); background: url(x)",
            "rgb(" + String(repeating: "9", count: 100) + ", 0, 0)", "#０９６９ＤＡ",
        ])
    func rejects(text: String) {
        #expect(SwatchColor(parsing: text) == nil)
    }

    // MARK: - Rendering

    @Test("the screenshot's examples get a swatch inside the code")
    func rendersSwatches() {
        let html = Self.render("`#0969DA` `rgb(9, 105, 218)` `hsl(212, 92%, 45%)`").html
        #expect(
            html
                == "<p>" + Self.swatch("#0969DA", "#0969da") + " " + Self.swatch("rgb(9, 105, 218)", "#0969da") + " "
                + Self.swatch("hsl(212, 92%, 45%)", "#096cdc") + "</p>\n")
    }

    @Test("off by default: color code spans render as plain code")
    func offByDefault() {
        #expect(Self.render("`#0969DA`", swatches: false).html == "<p><code>#0969DA</code></p>\n")
        #expect(RenderOptions().builtInPreprocessors.isEmpty)
    }

    @Test("code blocks, other code spans, image alt text, and text stay as they were")
    func leavesOthersAlone() {
        let markdown = "```\n#0969DA\n```\n\n#0969DA `x #0969DA` ![`#0969DA`](a.png)\n"
        #expect(Self.render(markdown).html == Self.render(markdown, swatches: false).html)
    }

    @Test("swatches work inside links, emphasis, headings, tables, and nested lists")
    func nested() {
        let html = Self.render(
            "# Brand `#0969DA`\n\n[**`#ffffff`**](x)\n\n| a |\n| - |\n| `rgb(0,0,0)` |\n\n- a\n  - `#000000`\n"
        ).html
        #expect(html.components(separatedBy: "peep-color-swatch").count == 5)
        #expect(html.contains("<h1 id=\"brand-0969da\">"))
    }

    @Test("the code text is escaped; the style only ever holds the re-serialized color")
    func escaping() {
        // cmark strips one space each side, so the literal is exactly the color.
        let html = Self.render("` #0969DA `").html
        #expect(html.contains(Self.swatch("#0969DA", "#0969da")))
        let hostile = Self.render("`#0969DA\"><script>`").html
        #expect(!hostile.contains("peep-color-swatch"))
        #expect(hostile.contains("#0969DA&quot;&gt;&lt;script&gt;"))
    }

    @Test("word count, heading text, and the title are the same with swatches")
    func sameTextAround() {
        let markdown = "# Use `#0969DA`\n\nPrimary `rgb(9, 105, 218)` here.\n"
        let drawn = Self.render(markdown)
        let plain = Self.render(markdown, swatches: false)
        #expect(drawn.wordCount == plain.wordCount)
        #expect(drawn.headings == plain.headings)
        #expect(drawn.title == plain.title)
    }

    @Test("spec mode never draws swatches")
    func specMode() {
        #expect(RenderOptions.spec.transforms.isEmpty)
    }

    @Test("Quick Look may run it")
    func quickLook() {
        #expect(QuickLookConfiguration.optionalPreprocessors.contains(.colorSwatches))
    }
}
