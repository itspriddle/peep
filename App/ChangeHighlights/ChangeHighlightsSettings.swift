import Foundation

/// Whether a live reload marks what changed (`App/Scripts/ChangeMarks.js`), and whether it then
/// scrolls to the first change, persisted in `UserDefaults`. Both off by default. One setting for
/// every window: turning highlights off clears the marks in open windows
/// (`DocumentWindowController+ChangeHighlights.swift`); turning either on applies from the next
/// reload. Scrolling is supplemental: it applies only while highlights are on
/// (`scrollsOnChange`), and keeps its value while they're off.
///
/// UI tests get in-memory values, off unless `-PeepUITestChangeHighlights YES` /
/// `-PeepUITestScrollToChanges YES`.
@MainActor
final class ChangeHighlightsSettings {
    /// The app's settings; in memory while hosting unit tests, which never read or write the
    /// reader's preference.
    static let shared = ChangeHighlightsSettings(
        isPersistent: !UITestHooks.isUITesting && !AppDelegate.isHostingUnitTests)

    /// Posted (object: the settings) after `isEnabled` or `scrollsToChanges` changes.
    static let didChangeNotification = Notification.Name("PeepChangeHighlightsSettingsDidChange")

    /// The `UserDefaults` key for `isEnabled`: a Bool, absent when off.
    static let key = "HighlightChanges"
    /// The `UserDefaults` key for `scrollsToChanges`: a Bool, absent when off.
    static let scrollKey = "ScrollToChanges"

    private let defaults: UserDefaults
    /// UI tests never read or write the reader's preference.
    private let isPersistent: Bool
    private var memoryValues: [String: Bool]

    init(defaults: UserDefaults = .standard, isPersistent: Bool = !UITestHooks.isUITesting) {
        self.defaults = defaults
        self.isPersistent = isPersistent
        memoryValues =
            isPersistent
            ? [:]
            : [Self.key: UITestHooks.enablesChangeHighlights, Self.scrollKey: UITestHooks.scrollsToChanges]
    }

    /// Whether live reloads mark the changed blocks. A stored value that isn't a Bool
    /// (preferences are untrusted input) reads as off.
    var isEnabled: Bool {
        get { value(forKey: Self.key) }
        set { setValue(newValue, forKey: Self.key) }
    }

    /// Whether a live reload that marked changes scrolls to the first one when none is in view.
    /// Applies only while `isEnabled` (see `scrollsOnChange`). A non-Bool stored value reads as off.
    var scrollsToChanges: Bool {
        get { value(forKey: Self.scrollKey) }
        set { setValue(newValue, forKey: Self.scrollKey) }
    }

    /// Whether a live reload should scroll to its first change: both settings on.
    var scrollsOnChange: Bool {
        isEnabled && scrollsToChanges
    }

    private func value(forKey key: String) -> Bool {
        guard isPersistent else {
            return memoryValues[key] ?? false
        }
        return defaults.object(forKey: key) as? Bool ?? false
    }

    private func setValue(_ newValue: Bool, forKey key: String) {
        guard newValue != value(forKey: key) else {
            return
        }
        if isPersistent {
            if newValue {
                defaults.set(true, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        } else {
            memoryValues[key] = newValue
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
