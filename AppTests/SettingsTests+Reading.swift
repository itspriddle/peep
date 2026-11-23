import Testing

@testable import PeepApp

/// Settings > Reading: change highlights, the supplemental scroll to the first change, and
/// bringing the window to the front on save.
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

    @Test("raising windows on change mirrors its store and writes through")
    func raiseOnChange() {
        let raise = RaiseOnChangeSettings(defaults: defaults, isPersistent: true)
        let model = model(raiseOnChangeSettings: raise)
        #expect(!model.raisesWindowOnChange)
        model.setRaisesWindowOnChange(true)
        #expect(raise.isEnabled)
        #expect(model.raisesWindowOnChange)
        raise.isEnabled = false
        #expect(!model.raisesWindowOnChange, "follows changes to the store")
    }
}
