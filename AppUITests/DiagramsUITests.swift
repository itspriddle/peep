import XCTest

/// Diagrams (M7): a document with every diagram block type. Mermaid (#117) is drawn in the
/// viewer: its node labels become their own text and the block's code leaves the page (hidden
/// behind the diagram). Maps and models (#115, #116) are drawn by PeepCore.
@MainActor
final class DiagramsUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    func testEveryDiagramTypeIsDrawn() throws {
        let peep = try PeepUITestApp.launch(openingFixture: "diagrams.md")
        self.peep = peep
        let window = peep.waitForWindow(titled: "Diagrams Fixture")
        peep.waitForRenderedText("The end.", in: window)

        // The code's text is one run ("A[Mermaid start node] --> …"); once drawn, it is hidden.
        let code = peep.renderedText("A[Mermaid start node]", in: window)
        let hidden = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: code)
        if XCTWaiter.wait(for: [hidden], timeout: PeepUITestApp.defaultTimeout) != .completed {
            peep.attachAccessibilityTree()
            XCTFail("the mermaid block's code is still shown")
        }
        // The diagram's labels are text of their own.
        peep.waitForRenderedText("Mermaid start node", in: window)
        XCTAssertTrue(peep.renderedText("Mermaid end node", in: window).exists)
        // Maps and models are drawn by PeepCore (#115, #116): their figures' captions, no code.
        for caption in ["GeoJSON map", "TopoJSON map", "STL model"] {
            XCTAssertTrue(peep.renderedText(caption, in: window).exists, caption)
        }
        XCTAssertFalse(peep.renderedText("solid tetrahedron", in: window).exists)
        XCTAssertFalse(peep.renderedText("FeatureCollection", in: window).exists)
    }

    /// Zoom and Open in Window (`DiagramControls.js`, `DiagramPanelController`): each diagram has
    /// controls; Open in Window shows it larger in a panel, which Escape closes.
    func testDiagramControlsZoomAndOpenInWindow() throws {
        let peep = try PeepUITestApp.launch(openingFixture: "diagrams.md")
        self.peep = peep
        let window = peep.waitForWindow(titled: "Diagrams Fixture")
        peep.waitForRenderedText("Mermaid start node", in: window)
        let webView = peep.webView(in: window)

        let zoomIn = webView.buttons["Zoom In"].firstMatch
        XCTAssertTrue(zoomIn.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "no zoom controls")
        XCTAssertEqual(webView.buttons.matching(identifier: "Open in Window").count, 4)
        zoomIn.click()
        webView.buttons["Reset Zoom"].firstMatch.click()

        webView.buttons["Open in Window"].firstMatch.click()
        let panel = peep.app.dialogs["diagram-window"]
        if !panel.waitForExistence(timeout: PeepUITestApp.defaultTimeout) {
            peep.attachAccessibilityTree()
            XCTFail("Open in Window showed no diagram window")
        }
        XCTAssertTrue(panel.title.hasPrefix("Diagrams Fixture"), panel.title)
        panel.typeKey(.escape, modifierFlags: [])
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: panel)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: PeepUITestApp.defaultTimeout), .completed)
        XCTAssertTrue(window.exists)
    }
}
