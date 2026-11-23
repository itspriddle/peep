import XCTest

/// "Bring the window to the front when a file is saved" (Settings > Reading): a save that
/// changes a document's text brings its window in front of Peep's other windows.
@MainActor
final class RaiseOnChangeUITests: XCTestCase {
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

    /// Writable copies of the named fixtures, in one temporary folder.
    private func copyFixtures(_ names: [String]) throws -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "peep-ui-raise-on-change-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.folder = folder
        return try names.map { name in
            let file = folder.appending(path: name)
            try FileManager.default.copyItem(at: try Fixtures.url(named: name), to: file)
            return file
        }
    }

    /// Launches Peep opening `files` in order (the last one in front).
    private func launch(opening files: [URL], arguments: [String] = []) -> PeepUITestApp {
        let paths = files.map { $0.path(percentEncoded: false) }
        let peep = PeepUITestApp.launch(
            arguments: ["-PeepUITestOpen", PeepUITestApp.propertyListArray(paths)] + arguments)
        self.peep = peep
        return peep
    }

    /// Waits until Peep's frontmost window is titled `title`.
    private func waitForFrontWindow(
        _ title: String, in peep: PeepUITestApp, file: StaticString = #filePath, line: UInt = #line
    ) {
        let predicate = NSPredicate { _, _ in peep.app.windows.firstMatch.title == title }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        if XCTWaiter().wait(for: [expectation], timeout: PeepUITestApp.defaultTimeout) != .completed {
            XCTFail(
                "Expected \(title) in front; front window: \(peep.app.windows.firstMatch.title)", file: file,
                line: line)
        }
    }

    /// Appends a paragraph to `file`, as an editor saving it would.
    private func append(_ text: String, to file: URL) throws {
        let source = try String(contentsOf: file, encoding: .utf8)
        try Data((source + "\n\(text)\n").utf8).write(to: file)
    }

    func testSaveBringsWindowToFront() throws {
        let files = try copyFixtures(["live-reload.md", "content-width.md"])
        let peep = launch(opening: files, arguments: ["-PeepUITestRaiseOnChange", "YES"])
        _ = peep.waitForWindow(titled: "Content Width Fixture")
        waitForFrontWindow("Content Width Fixture", in: peep)

        try append("Appended paragraph.", to: files[0])
        waitForFrontWindow("Live Reload Fixture", in: peep)
        peep.waitForRenderedText("Appended paragraph.", in: peep.window(titled: "Live Reload Fixture"))
    }

    func testOffByDefaultAndTurnedOnInSettings() throws {
        let files = try copyFixtures(["live-reload.md", "content-width.md"])
        let peep = launch(opening: files)
        let front = peep.waitForWindow(titled: "Content Width Fixture")
        waitForFrontWindow("Content Width Fixture", in: peep)

        let settings = peep.openSettings()
        peep.showSettingsPane("Reading")
        let toggle = settings.checkBoxes["settings-raise-on-change"]
        XCTAssertTrue(toggle.waitForExistence(timeout: PeepUITestApp.defaultTimeout))
        XCTAssertEqual(toggle.value as? Int, 0, "off by default")
        settings.typeKey("w", modifierFlags: .command)
        front.click()
        waitForFrontWindow("Content Width Fixture", in: peep)

        // Off: a save leaves the other window in front.
        try append("First appended paragraph.", to: files[0])
        peep.waitForRenderedText("First appended paragraph.", in: peep.window(titled: "Live Reload Fixture"))
        XCTAssertEqual(peep.app.windows.firstMatch.title, "Content Width Fixture")

        _ = peep.openSettings()
        peep.showSettingsPane("Reading")
        toggle.click()
        XCTAssertEqual(toggle.value as? Int, 1)
        settings.typeKey("w", modifierFlags: .command)
        front.click()
        waitForFrontWindow("Content Width Fixture", in: peep)

        try append("Second appended paragraph.", to: files[0])
        waitForFrontWindow("Live Reload Fixture", in: peep)
    }
}
