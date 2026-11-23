import AppKit
import PeepCore
import Testing
import WebKit

@testable import PeepApp

/// Hosted `WKWebView` tests for diagram zoom, pan, and Open in Window (`DiagramControls.js`,
/// `WebViewCoordinator+DiagramWindow.swift`, `DiagramPanelController`).
@MainActor
@Suite("Diagram controls", .serialized, .timeLimit(.minutes(1)))
struct DiagramControlsTests {
    static let document = """
        # Diagrams

        ```mermaid
        graph LR
          A[Start] --> B[End]
        ```

        ```geojson
        {"type": "Polygon", "coordinates": [[[0, 0], [10, 0], [10, 10], [0, 0]]]}
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

    func load(_ source: String = Self.document) async throws {
        try await coordinator.load(page(source), baseURL: nil)
        await coordinator.pendingDiagramRender?.value
        try await settle()
    }

    /// Lets the controls' MutationObserver run.
    func settle() async throws {
        try await evaluate("await new Promise((resolve) => setTimeout(resolve, 0));")
    }

    @discardableResult
    func evaluate(_ body: String, arguments: [String: Any] = [:]) async throws -> Any? {
        try await coordinator.webView.callAsyncJavaScript(
            body, arguments: arguments, in: nil, contentWorld: AppScripts.world)
    }

    func count(_ selector: String) async throws -> Int {
        let result = try await evaluate(
            "return document.querySelectorAll(selector).length;", arguments: ["selector": selector])
        return try #require(result as? NSNumber).intValue
    }

    /// A figure's zoom, as `peepDiagramControls.zoom` reports it.
    struct Zoom {
        var scale: Double
        var offsetX: Double
        var offsetY: Double
    }

    func zoom(_ index: Int) async throws -> Zoom {
        let result = try await evaluate("return peepDiagramControls.zoom(index);", arguments: ["index": index])
        let zoom = try #require(result as? [String: Any])
        return Zoom(
            scale: try #require(zoom["scale"] as? Double), offsetX: try #require(zoom["x"] as? Double),
            offsetY: try #require(zoom["y"] as? Double))
    }

    func perform(_ action: String, on index: Int = 0) async throws {
        try await evaluate(
            "peepDiagramControls.perform(index, action);", arguments: ["index": index, "action": action])
    }

    func figureHeight(_ index: Int = 0) async throws -> Double {
        let result = try await evaluate(
            "return document.querySelectorAll('figure.peep-diagram')[index].getBoundingClientRect().height;",
            arguments: ["index": index])
        return try #require(result as? Double)
    }

    @Test("every diagram, mermaid and renderer-drawn, gets one viewport and one set of controls")
    func attaches() async throws {
        try await load()
        #expect(try await count("figure.peep-diagram") == 2)
        #expect(try await count("figure.peep-diagram > .peep-diagram-viewport > svg") == 2)
        #expect(try await count("figure.peep-diagram > [data-peep-diagram-controls]") == 2)
        #expect(try await count("[data-peep-diagram-controls] button[aria-label='Open in Window']") == 2)
    }

    @Test("a mermaid redraw and a live reload swap get controls again, once")
    func reattaches() async throws {
        try await load()
        coordinator.webView.appearance = NSAppearance(named: .darkAqua)
        await coordinator.pendingDiagramRender?.value
        try await settle()
        #expect(try await count("[data-peep-diagram-controls]") == 2)
        #expect(try await count(".peep-diagram-viewport") == 2)
        try await coordinator.updateContent(
            with: page(Self.document.replacingOccurrences(of: "B[End]", with: "B[Reloaded]")), baseURL: nil)
        await coordinator.pendingDiagramRender?.value
        try await settle()
        #expect(try await count("[data-peep-diagram-controls]") == 2)
        #expect(try await count(".peep-diagram-viewport > svg") == 2)
    }

    @Test("zoom scales the diagram without changing the figure's height; reset undoes it")
    func zooms() async throws {
        try await load()
        let height = try await figureHeight()
        try await perform("zoom-in")
        try await perform("zoom-in")
        let zoomed = try await zoom(0)
        #expect(zoomed.scale > 1.5)
        #expect(try await figureHeight() == height)
        #expect(try await count(".peep-diagram-viewport[data-peep-zoomed]") == 1)
        try await perform("right")
        #expect(try await zoom(0).offsetX < zoomed.offsetX)
        try await perform("reset")
        let reset = try await zoom(0)
        #expect(reset.scale == 1 && reset.offsetX == 0 && reset.offsetY == 0)
        #expect(try await count(".peep-diagram-viewport[data-peep-zoomed]") == 0)
    }

    @Test("zoom stays between 1x and 8x, and panning never pulls in empty space")
    func clamps() async throws {
        try await load()
        try await perform("zoom-out")
        #expect(try await zoom(0).scale == 1)
        try await perform("left")
        #expect(try await zoom(0).offsetX == 0)
        for _ in 0..<20 {
            try await perform("zoom-in")
        }
        #expect(try await zoom(0).scale == 8)
        try await perform("up")
        #expect(try await zoom(0).offsetY <= 0)
    }

    @Test("Open in Window hands the window the diagram's SVG, without the zoom")
    func opensWindow() async throws {
        try await load()
        var received: [WebViewCoordinator.DiagramWindowContent] = []
        coordinator.diagramWindowHandler = { received.append($0) }
        try await perform("zoom-in", on: 1)
        await coordinator.openDiagramWindow(at: 1)
        let content = try #require(received.first)
        #expect(content.svg.hasPrefix("<svg"))
        #expect(content.svg.contains("peep-map"))
        #expect(!content.svg.contains("transform: translate"))
        #expect(content.label == "GeoJSON map")
        #expect(content.theme.id == coordinator.theme.id)
    }

    @Test("an index without a figure opens nothing")
    func missingFigure() async throws {
        try await load()
        var received = 0
        coordinator.diagramWindowHandler = { _ in received += 1 }
        await coordinator.openDiagramWindow(at: 7)
        await coordinator.openDiagramWindow(at: -1)
        #expect(received == 0)
    }

    @Test("the panel shows the diagram with JavaScript off and allows no navigation")
    func panel() async throws {
        let panel = DiagramPanelController()
        defer { panel.close() }
        let svg =
            #"<svg class="peep-map" viewBox="0 0 10 10"><a href="https://example.com"><path d="M0 0L10 10"/></a></svg>"#
        panel.show(.init(svg: svg, label: "GeoJSON map", theme: .github), documentTitle: "notes.md", over: window)
        #expect(panel.window?.title == "notes.md — GeoJSON map")
        #expect(panel.webView.configuration.defaultWebpagePreferences.allowsContentJavaScript == false)
        #expect(panel.webView.configuration.userContentController.userScripts.isEmpty)
        try await waitForLoad(panel.webView)
        #expect(panel.webView.url?.absoluteString == "about:blank")
        panel.zoomIn()
        #expect(panel.webView.magnification > 1)
        panel.resetZoom()
        #expect(panel.webView.magnification == 1)
    }

    private func waitForLoad(_ webView: WKWebView) async throws {
        for _ in 0..<200 where webView.isLoading || webView.url == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
