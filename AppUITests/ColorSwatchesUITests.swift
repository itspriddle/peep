import XCTest

/// Color swatches in the running app: Settings > Markdown's toggle is off by default and turns
/// them on for open documents. The swatch is a decorative empty element, absent from the
/// accessibility tree, so its markup and color are checked by `ColorSwatchWindowTests`.
@MainActor
final class ColorSwatchesUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    func testSettingsTurnsColorSwatchesOn() throws {
        let peep = try PeepUITestApp.launch(openingFixture: "color-swatches.md")
        self.peep = peep
        let window = peep.waitForWindow(titled: "Color Swatches")
        peep.waitForRenderedText("#0969DA", in: window)

        peep.openSettings()
        peep.showSettingsPane("Markdown")
        let toggle = peep.settingsWindow.checkBoxes["settings-preprocessor-colorSwatches"]
        XCTAssertTrue(toggle.waitForExistence(timeout: PeepUITestApp.defaultTimeout))
        XCTAssertEqual(toggle.value as? Int, 0, "off by default")
        toggle.click()
        XCTAssertEqual(toggle.value as? Int, 1)

        // Re-rendered in place: the code text is unchanged beside its swatch.
        peep.waitForRenderedText("#0969DA", in: window)
        XCTAssertTrue(peep.window(titled: "Color Swatches").exists)
    }
}
