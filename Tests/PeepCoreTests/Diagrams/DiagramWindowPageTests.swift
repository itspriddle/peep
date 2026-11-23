import Testing

@testable import PeepCore

@Suite("Diagram window page")
struct DiagramWindowPageTests {
    let page = DiagramWindowPage(title: "a <b> — Map", svg: "<svg viewBox=\"0 0 1 1\"></svg>", theme: .github)

    @Test("carries a CSP that allows no scripts and only data: images")
    func policy() {
        #expect(page.html.contains(ContentSecurityPolicy.diagramWindow.header))
        #expect(ContentSecurityPolicy.diagramWindow.header.contains("default-src 'none'"))
        #expect(ContentSecurityPolicy.diagramWindow.imageSources == ["data:"])
        #expect(!page.html.contains("<script"))
    }

    @Test("has the base and theme layers, an escaped title, and the SVG")
    func contents() {
        #expect(page.html.contains("<style id=\"\(ThemeLayer.base.name)\">"))
        #expect(page.html.contains(Theme.github.layerCSS))
        #expect(page.html.contains("<title>a &lt;b&gt; — Map</title>"))
        #expect(page.html.contains("<svg viewBox=\"0 0 1 1\"></svg>"))
    }

    @Test("fits the SVG to the window, over mermaid's inline max-width")
    func layout() {
        #expect(DiagramWindowPage.layoutCSS.contains("max-width: none !important"))
    }
}
