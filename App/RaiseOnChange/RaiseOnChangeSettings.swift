import Foundation

/// Settings > Reading's "Bring the window to the front when a file is saved", persisted in
/// `UserDefaults`, off by default. One setting for every window: while it is on, a live reload
/// that changed a document's text brings that document's window forward and activates the app
/// (`DocumentWindowController+RaiseOnChange.swift`); turning it on applies from the next reload.
///
/// UI tests get an in-memory value, off unless `-PeepUITestRaiseOnChange YES`.
@MainActor
final class RaiseOnChangeSettings {
    /// The app's setting; in memory while hosting unit tests, which never read or write the
    /// reader's preference.
    static let shared = RaiseOnChangeSettings(
        isPersistent: !UITestHooks.isUITesting && !AppDelegate.isHostingUnitTests)

    /// Posted (object: the settings) after `isEnabled` changes.
    static let didChangeNotification = Notification.Name("PeepRaiseOnChangeSettingsDidChange")

    /// The `UserDefaults` key for `isEnabled`: a Bool, absent when off.
    static let key = "RaiseWindowOnChange"

    private let defaults: UserDefaults
    /// UI tests never read or write the reader's preference.
    private let isPersistent: Bool
    private var memoryValue: Bool

    init(defaults: UserDefaults = .standard, isPersistent: Bool = !UITestHooks.isUITesting) {
        self.defaults = defaults
        self.isPersistent = isPersistent
        memoryValue = isPersistent ? false : UITestHooks.raisesWindowOnChange
    }

    /// Whether a live reload that changed a document's text brings its window to the front. A
    /// stored value that isn't a Bool (preferences are untrusted input) reads as off.
    var isEnabled: Bool {
        get {
            guard isPersistent else {
                return memoryValue
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
                memoryValue = newValue
            }
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }
}
