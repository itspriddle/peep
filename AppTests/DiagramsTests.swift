import AppKit
import PeepCore
import Testing
import WebKit

@testable import PeepApp

/// Hosted `WKWebView` tests for mermaid diagrams (#117): the vendored mermaid in its own content
/// world, under the page's CSP with page JavaScript off.
@MainActor
@Suite("Mermaid diagrams", .serialized, .timeLimit(.minutes(1)))
struct DiagramsTests {
    static let flowchart = """
        # Diagrams

        Before.

        ```mermaid
        graph TD
          A[Start] --> B{Is it?}
          B -->|Yes| C[OK]
        ```

        After.
        """

    let coordinator = WebViewCoordinator()
    /// Offscreen, never shown: gives the page a viewport to lay out in.
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered,
        defer: false)

    init() {
        window.isReleasedWhenClosed = false
        window.contentView = coordinator.webView
        coordinator.webView.appearance = NSAppearance(named: .aqua)
    }

    func page(_ source: String) -> RenderedPage {
        DocumentContent(source: source, fallbackTitle: "diagrams.md").page
    }

    /// Loads `source` and waits for its diagrams.
    func load(_ source: String) async throws {
        try await coordinator.load(page(source), baseURL: nil)
        await coordinator.pendingDiagramRender?.value
    }

    @discardableResult
    func evaluate(_ body: String, in world: WKContentWorld = AppScripts.world) async throws -> Any? {
        try await coordinator.webView.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: world)
    }

    func count(_ selector: String) async throws -> Int {
        let result = try await coordinator.webView.callAsyncJavaScript(
            "return document.querySelectorAll(selector).length;", arguments: ["selector": selector], in: nil,
            contentWorld: AppScripts.world)
        return try #require(result as? NSNumber).intValue
    }

    /// The computed fill of the first diagram's first node shape.
    func nodeFill() async throws -> String? {
        try await evaluate(
            """
            const shape = document.querySelector("figure.peep-diagram .node :is(rect, polygon)");
            return getComputedStyle(shape).fill;
            """) as? String
    }

    // MARK: Drawing

    @Test("a mermaid block becomes an SVG in a figure after its hidden code block")
    func drawsSVG() async throws {
        try await load(Self.flowchart)
        #expect(try await count("figure.peep-diagram > .peep-diagram-viewport > svg") == 1)
        #expect(try await count("pre[data-peep-diagram=rendered] + figure.peep-diagram") == 1)
        // The code stays in the page, hidden (ThemeBase), for Copy and find's sake.
        let hidden = try await evaluate(
            "return document.querySelector('pre[data-peep-diagram]').getClientRects().length;")
        #expect((hidden as? NSNumber)?.intValue == 0)
        // The figure holds the block's source line while the code is hidden.
        let line = try await evaluate(
            "return document.querySelector('figure.peep-diagram').getAttribute('data-source-line');")
        #expect(line as? String == "5")
        #expect(try await count("pre[data-source-line]") == 0)
        // mermaid's inline <style> applies under `style-src 'unsafe-inline'`: nodes get the
        // default theme's fill, not SVG's black.
        #expect(try await nodeFill() == "rgb(236, 236, 255)")
        #expect(coordinator.diagrams.renderedDark == false)
    }

    @Test("mermaid stays out of the page and app worlds; page scripts stay blocked")
    func isolation() async throws {
        try await load(Self.flowchart + "\n\n<script>document.title = 'pwned';</script>\n")
        #expect(try await count(".peep-diagram-viewport > svg") == 1)
        #expect(try await evaluate("return typeof globalThis.mermaid;") as? String == "undefined")
        let pageWorld = try await coordinator.webView.callAsyncJavaScript(
            "return typeof globalThis.mermaid;", arguments: [:], in: nil, contentWorld: .page)
        #expect(pageWorld as? String == "undefined")
        let diagramsWorld = try await evaluate(
            "return [typeof mermaid, typeof peepDiagrams, typeof globalThis.webkit?.messageHandlers?.changeMarks];",
            in: DiagramScripts.world)
        #expect(diagramsWorld as? [String] == ["object", "object", "undefined"])
        #expect(try await evaluate("return document.title;") as? String == "Diagrams")
        #expect(!coordinator.webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
    }

    @Test("a label with HTML in it yields no event attributes and runs nothing")
    func hostileLabel() async throws {
        try await load(
            """
            # Hostile

            ```mermaid
            graph TD
              A["<img src=x onerror=document.title='pwned'> <b onclick=x>bold</b>"]
              B["<script>document.title='pwned'</script>"]
              A --> B
              click A "javascript:document.title='pwned'"
            ```
            """)
        #expect(try await count(".peep-diagram-viewport > svg") == 1)
        let events = try await evaluate(
            """
            return [...document.querySelectorAll("*")]
              .filter((element) => [...element.attributes].some((a) => a.name.toLowerCase().startsWith("on")))
              .length;
            """)
        #expect((events as? NSNumber)?.intValue == 0)
        #expect(try await count("figure.peep-diagram script") == 0)
        #expect(try await count("figure.peep-diagram [href^='javascript:' i]") == 0)
        #expect(try await evaluate("return document.title;") as? String == "Hostile")
    }

    @Test("a block mermaid can't draw stays visible with a note")
    func error() async throws {
        try await load("# Broken\n\n```mermaid\ngraph TD\n  A[ --> \n```\n\n```mermaid\ngraph LR\n  X --> Y\n```\n")
        #expect(try await count("pre[data-peep-diagram=error] + p.peep-diagram-error[role=note]") == 1)
        #expect(try await count(".peep-diagram-viewport > svg") == 1)
        let visible = try await evaluate(
            "return document.querySelector('pre[data-peep-diagram=error]').getClientRects().length;")
        #expect((visible as? NSNumber)?.intValue ?? 0 > 0)
        // No scratch element or error SVG is left in the body.
        #expect(try await count("body > [id^='dpeep-diagram-']") == 0)
    }

    // MARK: Laziness

    @Test("a page without mermaid blocks never loads mermaid")
    func lazy() async throws {
        try await coordinator.load(page("# Plain\n\n```js\nlet mermaid = 1;\n```\n"), baseURL: nil)
        #expect(coordinator.pendingDiagramRender == nil)
        #expect(coordinator.diagrams.installedGeneration == nil)
        let type = try await evaluate("return typeof globalThis.mermaid;", in: DiagramScripts.world)
        #expect(type as? String == "undefined")
    }

    @Test("a live reload swap draws the new blocks with the mermaid already in the page")
    func liveReload() async throws {
        try await load(Self.flowchart)
        let installed = try #require(coordinator.diagrams.installedGeneration)
        // A marker in the diagrams world: a second evaluation of the scripts would replace it.
        try await evaluate("globalThis.peepTestMarker = 1;", in: DiagramScripts.world)
        try await coordinator.updateContent(
            with: page(Self.flowchart.replacingOccurrences(of: "C[OK]", with: "C[Reloaded]")), baseURL: nil)
        await coordinator.pendingDiagramRender?.value
        #expect(coordinator.diagrams.installedGeneration == installed)
        #expect(try await evaluate("return globalThis.peepTestMarker;", in: DiagramScripts.world) as? Int == 1)
        let text = try await evaluate("return document.querySelector('figure.peep-diagram').textContent;")
        #expect((text as? String)?.contains("Reloaded") == true)
        #expect(try await count("figure.peep-diagram") == 1)

        // Swapping in a page without mermaid leaves nothing behind.
        try await coordinator.updateContent(with: page("# Plain\n\nText."), baseURL: nil)
        await coordinator.pendingDiagramRender?.value
        #expect(try await count("figure.peep-diagram") == 0)
    }

    @Test("an appearance change redraws the diagrams in dark colors and back")
    func appearance() async throws {
        try await load(Self.flowchart)
        let light = try await evaluate("return document.querySelector('figure.peep-diagram svg').id;") as? String
        coordinator.webView.appearance = NSAppearance(named: .darkAqua)
        await coordinator.pendingDiagramRender?.value
        #expect(coordinator.diagrams.renderedDark == true)
        let dark = try await evaluate("return document.querySelector('figure.peep-diagram svg').id;") as? String
        #expect(dark != light, "drawn again")
        #expect(try await count("figure.peep-diagram") == 1)
        #expect(try await nodeFill() != "rgb(236, 236, 255)")
        coordinator.webView.appearance = NSAppearance(named: .aqua)
        await coordinator.pendingDiagramRender?.value
        #expect(coordinator.diagrams.renderedDark == false)
    }

    /// The page Settings > Markdown > Render diagrams off renders (`RenderOptions.diagrams`).
    func pageWithoutDiagrams(_ source: String) -> RenderedPage {
        var preferences = MarkdownPreferences.default
        preferences.rendersDiagrams = false
        return DocumentContent(source: source, fallbackTitle: "diagrams.md", preferences: preferences).page
    }

    @Test("turning Render diagrams off shows the code again; on draws them")
    func toggle() async throws {
        try await load(Self.flowchart)
        // A Settings change re-renders the document and swaps it in place.
        try await coordinator.replaceContent(with: pageWithoutDiagrams(Self.flowchart), baseURL: nil)
        await coordinator.pendingDiagramRender?.value
        #expect(try await count("figure.peep-diagram") == 0)
        #expect(try await count("pre[data-peep-diagram]") == 0)
        #expect(try await count("pre[data-source-line='5']") == 1)
        try await coordinator.replaceContent(with: page(Self.flowchart), baseURL: nil)
        await coordinator.pendingDiagramRender?.value
        #expect(try await count("figure.peep-diagram.peep-diagram-mermaid > .peep-diagram-viewport > svg") == 1)
    }

    @Test("off from the start, a mermaid page never loads mermaid")
    func offFromStart() async throws {
        try await coordinator.load(pageWithoutDiagrams(Self.flowchart), baseURL: nil)
        #expect(coordinator.pendingDiagramRender == nil)
        #expect(try await count("pre > code.language-mermaid") == 1)
        let type = try await evaluate("return typeof globalThis.mermaid;", in: DiagramScripts.world)
        #expect(type as? String == "undefined")
    }

    @Test("maps the renderer draws are left alone")
    func rendererDiagrams() async throws {
        let map = """
            ```geojson
            {"type": "Polygon", "coordinates": [[[0, 0], [10, 0], [10, 10], [0, 0]]]}
            ```
            """
        try await load(Self.flowchart + "\n\n" + map + "\n")
        #expect(try await count("figure.peep-diagram") == 2)
        #expect(try await count("figure.peep-diagram-mermaid") == 1)
        #expect(try await count("figure.peep-diagram-geojson") == 1)
    }
}
