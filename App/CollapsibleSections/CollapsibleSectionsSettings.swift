import Foundation

/// Whether clicking a heading collapses its section (`App/Scripts/CollapsibleSections.js`),
/// persisted in `UserDefaults`. Off by default. One setting for every window: open windows
/// follow it live (`DocumentWindowController+CollapsibleSections.swift`).
///
/// UI tests get an in-memory value, off unless `-PeepUITestCollapsibleSections YES`.
@MainActor
final class CollapsibleSectionsSettings {
    /// The app's settings.
    static let shared = CollapsibleSectionsSettings()

    /// Posted (object: the settings) after `isEnabled` changes.
    static let didChangeNotification = Notification.Name("PeepCollapsibleSectionsSettingsDidChange")

    /// The `UserDefaults` key: a Bool, absent when off.
    static let key = "CollapsibleSections"

    private let defaults: UserDefaults
    /// UI tests never read or write the reader's preference.
    private let isPersistent: Bool
    private var memoryEnabled: Bool

    init(defaults: UserDefaults = .standard, isPersistent: Bool = !UITestHooks.isUITesting) {
        self.defaults = defaults
        self.isPersistent = isPersistent
        memoryEnabled = !isPersistent && UITestHooks.enablesCollapsibleSections
    }

    /// Whether top-level headings fold their sections when clicked. A stored value that isn't a
    /// Bool (preferences are untrusted input) reads as off.
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
