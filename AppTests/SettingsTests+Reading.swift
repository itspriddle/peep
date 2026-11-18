import Testing

@testable import PeepApp

/// Settings > Reading: change highlights and the supplemental scroll to the first change.
extension SettingsTests {
    @Test("change highlights and scrolling to changes mirror their store and write through")
    func changeHighlights() {
        let highlights = ChangeHighlightsSettings(defaults: defaults, isPersistent: true)
        let model = model(changeHighlightsSettings: highlights)
        #expect(!model.highlightsChanges)
        #expect(!model.scrollsToChanges)
        model.setHighlightsChanges(true)
        model.setScrollsToChanges(true)
        #expect(highlights.scrollsOnChange)
        #expect(model.highlightsChanges)
        #expect(model.scrollsToChanges)
        highlights.scrollsToChanges = false
        #expect(!model.scrollsToChanges, "follows changes to the store")
    }
}
