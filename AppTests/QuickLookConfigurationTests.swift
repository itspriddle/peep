import Foundation
import PeepCore
import Testing

@testable import PeepApp

/// Quick Look's settings (`QuickLookConfigurationPublisher`, Settings > General's Quick Look
/// theme): what the app publishes for its extensions, over throwaway defaults for both the app's
/// stores and the App Group store.
@MainActor
@Suite("Quick Look configuration", .serialized)
final class QuickLookConfigurationTests {
    let appDefaults: ThrowawayDefaults
    let groupDefaults: ThrowawayDefaults
    let themesFolder: URL

    init() throws {
        appDefaults = try ThrowawayDefaults("peep-quicklook-app")
        groupDefaults = try ThrowawayDefaults("peep-quicklook-group")
        themesFolder = FileManager.default.temporaryDirectory.appending(
            path: "peep-quicklook-themes-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: themesFolder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: themesFolder)
    }

    private func published() -> QuickLookConfiguration {
        QuickLookConfiguration(data: groupDefaults.defaults.data(forKey: QuickLookConfiguration.defaultsKey))
    }

    private func stores() -> (ThemeSettings, MarkdownSettings) {
        (
            ThemeSettings(defaults: appDefaults.defaults, isPersistent: true),
            MarkdownSettings(defaults: appDefaults.defaults, isPersistent: true)
        )
    }

    @Test("the Quick Look theme follows the default theme until one is picked")
    func quickLookTheme() {
        let (themes, _) = stores()
        #expect(themes.quickLookTheme.id == "github")
        themes.defaultThemeID = "serif"
        #expect(themes.quickLookTheme.id == "serif")
        themes.quickLookThemeID = "document"
        #expect(themes.quickLookTheme.id == "document")
        #expect(appDefaults.defaults.string(forKey: ThemeSettings.quickLookThemeKey) == "document")
        themes.quickLookThemeID = "custom:gone.css"
        #expect(themes.quickLookTheme.id == "serif")
        themes.quickLookThemeID = nil
        #expect(appDefaults.defaults.object(forKey: ThemeSettings.quickLookThemeKey) == nil)
    }

    @Test("publishes on start and after each theme or Markdown change")
    func publishes() {
        let (themes, markdown) = stores()
        let publisher = QuickLookConfigurationPublisher(
            themeSettings: themes, markdownSettings: markdown, themesFolder: themesFolder,
            store: groupDefaults.defaults)
        publisher.start()
        defer { publisher.stop() }
        #expect(published() == QuickLookConfiguration(themeID: "github", flavorID: "gfm"))

        themes.defaultThemeID = "serif"
        #expect(published().themeID == "serif")
        themes.quickLookThemeID = "document"
        #expect(published().themeID == "document")

        markdown.defaultFlavorID = "commonmark"
        markdown.frontmatterDisplay = .table
        markdown.builtInPreprocessors = [.wikiLinks]
        #expect(published().flavor == .commonmark)
        #expect(published().frontmatter == .table)
        #expect(published().preprocessors == [.wikiLinks])
    }

    @Test("a custom Quick Look theme is published with its file's text, and reloads with it")
    func customTheme() throws {
        let css = "/* peep-theme\n   name: Mine\n*/\nbody { color: #123456; }\n"
        let file = themesFolder.appending(path: "mine.css")
        try css.write(to: file, atomically: true, encoding: .utf8)
        let (themes, markdown) = stores()
        themes.apply(CustomThemeFolder(url: themesFolder).load())
        themes.quickLookThemeID = "custom:mine.css"
        let publisher = QuickLookConfigurationPublisher(
            themeSettings: themes, markdownSettings: markdown, themesFolder: themesFolder,
            store: groupDefaults.defaults)
        publisher.start()
        defer { publisher.stop() }
        #expect(published().customTheme == QuickLookCustomTheme(fileName: "mine.css", css: css))
        #expect(published().themeRegistry.contains(id: "custom:mine.css"))

        let edited = css.replacingOccurrences(of: "#123456", with: "#654321")
        try edited.write(to: file, atomically: true, encoding: .utf8)
        themes.apply(CustomThemeFolder(url: themesFolder).load())
        #expect(published().customTheme?.css == edited)

        try FileManager.default.removeItem(at: file)
        themes.apply(CustomThemeFolder(url: themesFolder).load())
        #expect(published().themeID == "github")
        #expect(published().customTheme == nil)
    }

    @Test("never publishes custom programs or the window-only settings")
    func onlyPresentation() throws {
        let (themes, markdown) = stores()
        let publisher = QuickLookConfigurationPublisher(
            themeSettings: themes, markdownSettings: markdown, themesFolder: nil, store: groupDefaults.defaults)
        publisher.publish()
        let data = try #require(groupDefaults.defaults.data(forKey: QuickLookConfiguration.defaultsKey))
        let keys = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
        #expect(Set(keys) == ["themeID", "flavorID", "frontmatterDisplay", "builtInPreprocessors"])
    }

    @Test("a build without a team has no App Group store")
    func noTeam() {
        #expect(QuickLookConfigurationPublisher.appGroupStore(bundle: Bundle(for: Marker.self)) == nil)
    }

    private final class Marker {}
}
