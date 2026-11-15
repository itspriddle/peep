import XCTest

/// Collapsible sections (Settings > General): with the setting on, clicking a heading folds its
/// section, and View > Collapse All Sections / Expand All Sections fold the whole document.
@MainActor
final class CollapsibleSectionsUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    private func launch(enabled: Bool = true) throws -> PeepUITestApp {
        let peep = try PeepUITestApp.launch(
            openingFixture: "sections.md",
            arguments: enabled ? ["-PeepUITestCollapsibleSections", "YES"] : [])
        self.peep = peep
        peep.waitForWindow(titled: "Sections Fixture")
        peep.waitForRenderedText("Nested section body.")
        return peep
    }

    private func waitUntil(
        _ text: String, isShown shown: Bool, in peep: PeepUITestApp, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let element = peep.renderedText(text)
        let predicate = NSPredicate(format: "exists == %@", NSNumber(value: shown))
        let result = XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: PeepUITestApp.defaultTimeout)
        if result != .completed {
            peep.attachAccessibilityTree()
        }
        XCTAssertEqual(
            result, .completed, "\"\(text)\" should be \(shown ? "shown" : "hidden")", file: file, line: line)
    }

    private func chooseViewItem(_ title: String, in peep: PeepUITestApp) {
        let view = peep.app.menuBars.menuBarItems["View"]
        view.click()
        view.menuItems[title].click()
    }

    func testClickingAHeadingFoldsItsSection() throws {
        let peep = try launch()

        peep.renderedText("Second Section").click()
        waitUntil("Second section body.", isShown: false, in: peep)
        waitUntil("Nested section body.", isShown: false, in: peep)
        waitUntil("First section body.", isShown: true, in: peep)

        peep.renderedText("Second Section").click()
        waitUntil("Second section body.", isShown: true, in: peep)
        waitUntil("Nested section body.", isShown: true, in: peep)
    }

    func testCollapseAndExpandAll() throws {
        let peep = try launch()

        chooseViewItem("Collapse All Sections", in: peep)
        waitUntil("Intro paragraph.", isShown: false, in: peep)
        waitUntil("Sections Fixture", isShown: true, in: peep)

        chooseViewItem("Expand All Sections", in: peep)
        waitUntil("Intro paragraph.", isShown: true, in: peep)
        waitUntil("Nested section body.", isShown: true, in: peep)
    }

    func testHeadingsDoNotFoldWhileOff() throws {
        let peep = try launch(enabled: false)

        peep.renderedText("Second Section").click()
        waitUntil("Second section body.", isShown: true, in: peep)
        let view = peep.app.menuBars.menuBarItems["View"]
        view.click()
        XCTAssertFalse(view.menuItems["Collapse All Sections"].isEnabled)
        peep.app.typeKey(.escape, modifierFlags: [])
    }
}
