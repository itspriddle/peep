import XCTest

/// "Highlight changes when a file is saved" (Settings > General): after a live reload, a change
/// out of view shows the status bar's changes item, and clicking it scrolls to the change.
@MainActor
final class ChangeHighlightsUITests: XCTestCase {
    private var peep: PeepUITestApp?
    private var folder: URL?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
        if let folder {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// A writable copy of the `live-reload.md` fixture (150 one-line paragraphs).
    private func copyFixture() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "peep-ui-change-highlights-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.folder = folder
        let file = folder.appending(path: "live-reload.md")
        try FileManager.default.copyItem(at: try Fixtures.url(named: "live-reload.md"), to: file)
        return file
    }

    func testChangeOutOfViewIsCountedAndReachable() throws {
        let file = try copyFixture()
        let peep = PeepUITestApp.launch(opening: file, arguments: ["-PeepUITestChangeHighlights", "YES"])
        self.peep = peep
        let window = peep.waitForWindow(titled: "Live Reload Fixture")
        peep.waitForRenderedText("Paragraph 1.", in: window)

        let source = try String(contentsOf: file, encoding: .utf8)
        try Data(source.replacingOccurrences(of: "Paragraph 140.", with: "Paragraph 140, edited.").utf8)
            .write(to: file)
        peep.waitForRenderedText("Paragraph 140, edited.", in: window)

        let item = window.descendants(matching: .any)["changes-item"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "the changes item")
        XCTAssertEqual(item.label, "1 change below")
        XCTAssertTrue(peep.renderedText("Paragraph 1.", in: window).isHittable, "the view didn't move")

        item.click()
        let edited = peep.renderedText("Paragraph 140, edited.", in: window)
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: edited)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: PeepUITestApp.defaultTimeout), .completed)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: item)
        XCTAssertEqual(
            XCTWaiter().wait(for: [gone], timeout: PeepUITestApp.defaultTimeout), .completed,
            "the item goes once the change is in view")
    }

    func testOffByDefaultAndTurnedOnInSettings() throws {
        let file = try copyFixture()
        let peep = PeepUITestApp.launch(opening: file)
        self.peep = peep
        let window = peep.waitForWindow(titled: "Live Reload Fixture")
        peep.waitForRenderedText("Paragraph 1.", in: window)

        let source = try String(contentsOf: file, encoding: .utf8)
        try Data(source.replacingOccurrences(of: "Paragraph 140.", with: "Paragraph 140, edited.").utf8)
            .write(to: file)
        peep.waitForRenderedText("Paragraph 140, edited.", in: window)
        let item = window.descendants(matching: .any)["changes-item"].firstMatch
        XCTAssertFalse(item.waitForExistence(timeout: 2))

        // Settings > Reading turns it on for the next save.
        let settings = peep.openSettings()
        peep.showSettingsPane("Reading")
        let toggle = settings.checkBoxes["settings-highlight-changes"]
        XCTAssertTrue(toggle.waitForExistence(timeout: PeepUITestApp.defaultTimeout))
        XCTAssertEqual(toggle.value as? Int, 0)
        toggle.click()
        XCTAssertEqual(toggle.value as? Int, 1)
        settings.typeKey("w", modifierFlags: .command)

        let edited = try String(contentsOf: file, encoding: .utf8)
        try Data(edited.replacingOccurrences(of: "Paragraph 130.", with: "Paragraph 130, edited.").utf8)
            .write(to: file)
        XCTAssertTrue(item.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "the changes item")
    }

    func testScrollsToChangeOnSave() throws {
        let file = try copyFixture()
        let peep = PeepUITestApp.launch(
            opening: file,
            arguments: ["-PeepUITestChangeHighlights", "YES", "-PeepUITestScrollToChanges", "YES"])
        self.peep = peep
        let window = peep.waitForWindow(titled: "Live Reload Fixture")
        peep.waitForRenderedText("Paragraph 1.", in: window)

        let source = try String(contentsOf: file, encoding: .utf8)
        try Data(source.replacingOccurrences(of: "Paragraph 140.", with: "Paragraph 140, edited.").utf8)
            .write(to: file)
        peep.waitForRenderedText("Paragraph 140, edited.", in: window)
        let edited = peep.renderedText("Paragraph 140, edited.", in: window)
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: edited)
        XCTAssertEqual(
            XCTWaiter().wait(for: [hittable], timeout: PeepUITestApp.defaultTimeout), .completed,
            "the window scrolled to the change without a click")
    }

    func testScrollToggleFollowsHighlights() throws {
        let file = try copyFixture()
        let peep = PeepUITestApp.launch(opening: file)
        self.peep = peep
        _ = peep.waitForWindow(titled: "Live Reload Fixture")

        let settings = peep.openSettings()
        peep.showSettingsPane("Reading")
        let highlight = settings.checkBoxes["settings-highlight-changes"]
        let scroll = settings.checkBoxes["settings-scroll-to-changes"]
        XCTAssertTrue(scroll.waitForExistence(timeout: PeepUITestApp.defaultTimeout))
        XCTAssertFalse(scroll.isEnabled, "disabled while highlights are off")
        highlight.click()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: scroll)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: PeepUITestApp.defaultTimeout), .completed)
        scroll.click()
        XCTAssertEqual(scroll.value as? Int, 1)
    }
}
