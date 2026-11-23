import XCTest

/// The custom processor (#106), configured with the Debug-only `-PeepUITestProcessor` hook so
/// tests never depend on the reader's settings: its sanitized output renders, a failing
/// processor falls back to Peep's renderer with the bar instead of an alert, and turning it
/// back on in Settings > Programs needs the warning.
@MainActor
final class CustomProcessorUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    private func launch(script path: String) throws -> PeepUITestApp {
        let peep = try PeepUITestApp.launch(
            openingFixture: "processor.md", arguments: try PeepUITestApp.processorArguments(fixture: path))
        self.peep = peep
        return peep
    }

    func testProcessorOutputRenders() throws {
        let peep = try launch(script: "processors/html.sh")
        let window = peep.waitForWindow(titled: "Processor fixture")
        peep.waitForRenderedText("Rendered by the processor.", in: window)
        XCTAssertFalse(peep.processorFailureBar(in: window).exists)
    }

    func testFailingProcessorFallsBackWithBar() throws {
        let peep = try launch(script: "preprocessors/fail.sh")
        let window = peep.waitForWindow(titled: "Processor fixture")
        peep.waitForRenderedText("Rendered by Peep.", in: window)

        let bar = peep.processorFailureBar(in: window)
        XCTAssertTrue(bar.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "failure bar")
        let message = bar.descendants(matching: .any)["processor-failure-message"].firstMatch
        XCTAssertTrue(message.displayedText.contains("The processor exited with status 3"), message.displayedText)
        XCTAssertEqual(peep.app.dialogs.count, 0, "no alert")
        XCTAssertFalse(peep.preprocessorFailureBar(in: window).exists)
    }

    func testTurningOnAgainNeedsTheWarning() throws {
        let peep = try launch(script: "processors/html.sh")
        let window = peep.waitForWindow(titled: "Processor fixture")
        peep.waitForRenderedText("Rendered by the processor.", in: window)

        let settings = peep.openSettings()
        peep.showSettingsPane("Programs")
        let toggle = settings.checkBoxes["settings-custom-processor"]
        XCTAssertTrue(toggle.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "toggle")
        XCTAssertEqual(toggle.value as? Int, 1)
        XCTAssertEqual(settings.checkBoxes["settings-custom-preprocessor"].value as? Int, 0, "separate settings")

        // Off: open windows render with Peep, in place.
        toggle.click()
        peep.waitForRenderedText("Rendered by Peep.", in: window)

        // On: the warning first.
        toggle.click()
        let turnOn = settings.buttons["settings-custom-processor-confirm"].firstMatch
        XCTAssertTrue(turnOn.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "the warning")
        turnOn.click()
        XCTAssertEqual(toggle.value as? Int, 1)
        peep.waitForRenderedText("Rendered by the processor.", in: window)
    }
}
