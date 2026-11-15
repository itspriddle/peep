import PeepCore
import Testing

@testable import PeepApp

/// Settings > Quick Look's theme picker.
extension SettingsTests {
    @Test("the Quick Look theme picker follows the default until a theme is picked")
    func quickLookTheme() {
        let themes = themeSettings()
        let model = model(themeSettings: themes)
        #expect(model.quickLookThemeID == SettingsModel.quickLookFollowsDefault)
        model.setQuickLookTheme(id: "serif")
        #expect(model.quickLookThemeID == "serif")
        #expect(defaults.string(forKey: ThemeSettings.quickLookThemeKey) == "serif")
        model.setQuickLookTheme(id: "custom:missing.css")
        #expect(model.quickLookThemeID == "serif")
        model.setQuickLookTheme(id: SettingsModel.quickLookFollowsDefault)
        #expect(model.quickLookThemeID == SettingsModel.quickLookFollowsDefault)
        #expect(themes.quickLookThemeID == nil)
    }
}
