import Foundation
import PeepCore
import os

/// Publishes what Quick Look renders with (`QuickLookConfiguration`) to the App Group's defaults,
/// where the sandboxed Quick Look extension reads it: Quick Look's theme (Settings > General,
/// `ThemeSettings.quickLookTheme`, with a custom theme's file text), and Settings > Markdown's
/// flavor, frontmatter display, and built-in preprocessors. Custom programs are never published.
///
/// It writes when a setting it reads changes (`ThemeSettings` and `MarkdownSettings` change
/// notifications, which include custom theme files changing) and only when the configuration
/// differs from the stored one. Off in hosted unit tests and UI tests (`AppDelegate`), and in
/// builds without a team, which have no App Group (`QuickLookConfiguration.appGroupIdentifier`).
@MainActor
final class QuickLookConfigurationPublisher {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "peep", category: "quicklook")

    private let themeSettings: ThemeSettings
    private let markdownSettings: MarkdownSettings
    /// The custom themes folder, for the picked custom theme's file; `nil` when custom themes
    /// are off.
    private let themesFolder: URL?
    private let store: UserDefaults
    private var observers: [any NSObjectProtocol] = []

    init(themeSettings: ThemeSettings, markdownSettings: MarkdownSettings, themesFolder: URL?, store: UserDefaults) {
        self.themeSettings = themeSettings
        self.markdownSettings = markdownSettings
        self.themesFolder = themesFolder
        self.store = store
    }

    /// The App Group's defaults, or `nil` in a build without one.
    static func appGroupStore(bundle: Bundle = .main) -> UserDefaults? {
        guard
            let group = QuickLookConfiguration.appGroupIdentifier(
                infoValue: bundle.object(forInfoDictionaryKey: QuickLookConfiguration.appGroupInfoKey))
        else {
            return nil
        }
        return UserDefaults(suiteName: group)
    }

    /// Publishes now and after every change. Both stores post on the main actor, so the
    /// observers run there, synchronously.
    func start() {
        guard observers.isEmpty else {
            return
        }
        let center = NotificationCenter.default
        for (name, object) in [
            (ThemeSettings.didChangeNotification, themeSettings as AnyObject),
            (MarkdownSettings.didChangeNotification, markdownSettings as AnyObject),
        ] {
            observers.append(
                center.addObserver(forName: name, object: object, queue: nil) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.publish()
                    }
                })
        }
        publish()
    }

    /// Stops publishing. What was published stays.
    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    /// The configuration for the current settings.
    var configuration: QuickLookConfiguration {
        let theme = themeSettings.quickLookTheme
        let preferences = markdownSettings.preferences
        return QuickLookConfiguration(
            themeID: theme.id,
            customTheme: customTheme(id: theme.id),
            flavorID: preferences.flavor.id,
            frontmatterDisplay: preferences.frontmatterDisplay,
            builtInPreprocessors: preferences.builtInPreprocessors,
            rendersDiagrams: preferences.rendersDiagrams)
    }

    /// Writes `configuration` when it differs from what is stored.
    func publish() {
        guard let data = configuration.encoded() else {
            Self.logger.error("Quick Look configuration didn't encode")
            return
        }
        if store.data(forKey: QuickLookConfiguration.defaultsKey) != data {
            store.set(data, forKey: QuickLookConfiguration.defaultsKey)
        }
    }

    /// The text of the custom theme `id` names, read from its file as the library reads it
    /// (`CustomThemeFolder.readTheme`). The extension checks it again before using it.
    private func customTheme(id: String) -> QuickLookCustomTheme? {
        guard id.hasPrefix(CustomTheme.idPrefix), let themesFolder else {
            return nil
        }
        let fileName = String(id.dropFirst(CustomTheme.idPrefix.count))
        guard CustomThemeFolder.isThemeFileName(fileName), !fileName.contains("/") else {
            return nil
        }
        do throws(CustomThemeProblem) {
            let css = try CustomThemeFolder.readTheme(
                at: themesFolder.appending(path: fileName, directoryHint: .notDirectory))
            return QuickLookCustomTheme(fileName: fileName, css: css)
        } catch {
            Self.logger.error("Quick Look theme \(fileName, privacy: .public) unreadable: \(String(describing: error))")
            return nil
        }
    }
}
