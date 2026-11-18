import Foundation

/// Whether a live reload marks what changed (`App/Scripts/ChangeMarks.js`), persisted in
/// `UserDefaults`. Off by default. One setting for every window: turning it off clears the marks
/// in open windows (`DocumentWindowController+ChangeHighlights.swift`); turning it on applies
/// from the next reload.
///
/// UI tests get an in-memory value, off unless `-PeepUITestChangeHighlights YES`.
@MainActor
final class ChangeHighlightsSettings {
    /// The app's settings; in memory while hosting unit tests, which never read or write the
    /// reader's preference.
    static let shared = ChangeHighlightsSettings(
        isPersistent: !UITestHooks.isUITesting && !AppDelegate.isHostingUnitTests)

    /// Posted (object: the settings) after `isEnabled` changes.
    static let didChangeNotification = Notification.Name("PeepChangeHighlightsSettingsDidChange")

    /// The `UserDefaults` key: a Bool, absent when off.
    static let key = "HighlightChanges"

    private let defaults: UserDefaults
    /// UI tests never read or write the reader's preference.
    private let isPersistent: Bool
    private var memoryEnabled: Bool

    init(defaults: UserDefaults = .standard, isPersistent: Bool = !UITestHooks.isUITesting) {
        self.defaults = defaults
        self.isPersistent = isPersistent
        memoryEnabled = !isPersistent && UITestHooks.enablesChangeHighlights
    }

    /// Whether live reloads mark the changed blocks. A stored value that isn't a Bool
    /// (preferences are untrusted input) reads as off.
    var isEnabled: Bool {
        get {
            guard isPersistent else {
                return memoryEnabled
            }
            return defaults.object(forKey: Self.key) as? Bool ?? false
        }
        set {
            guard newValue != isEnabled else {
                return
            }
            if isPersistent {
                if newValue {
                    defaults.set(true, forKey: Self.key)
                } else {
                    defaults.removeObject(forKey: Self.key)
                }
            } else {
                memoryEnabled = newValue
            }
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }
}
