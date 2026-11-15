import XCTest

extension PeepUITestApp {
    /// The launch arguments that start the app with fixture script `name` (in
    /// `Fixtures/preprocessors`) as its custom preprocessor (#57).
    ///
    /// The scripts are bundle fixtures (executable in git) rather than files the test writes:
    /// the runner is sandboxed, files it writes are quarantined, and the system refuses to run
    /// a quarantined script (`EPERM`), as it would a downloaded one.
    static func preprocessorArguments(fixture name: String) throws -> [String] {
        ["-PeepUITestPreprocessor", try Fixtures.url(named: "preprocessors/\(name)").path(percentEncoded: false)]
    }

    /// The custom preprocessor's failure bar in `window`.
    func preprocessorFailureBar(in window: XCUIElement) -> XCUIElement {
        window.descendants(matching: .any)["preprocessor-failure-bar"].firstMatch
    }
}

extension PeepUITestApp {
    /// The launch arguments that start the app with fixture script `path` (relative to
    /// `Fixtures`, e.g. `processors/html.sh`) as its custom processor (#106). Bundle fixtures
    /// for the same reason as `preprocessorArguments(fixture:)`.
    static func processorArguments(fixture path: String) throws -> [String] {
        ["-PeepUITestProcessor", try Fixtures.url(named: path).path(percentEncoded: false)]
    }

    /// The custom processor's failure bar in `window`.
    func processorFailureBar(in window: XCUIElement) -> XCUIElement {
        window.descendants(matching: .any)["processor-failure-bar"].firstMatch
    }
}
