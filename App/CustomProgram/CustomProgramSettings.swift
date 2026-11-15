import Foundation
import PeepCore

/// The custom preprocessor (#57) or processor (#106) a render runs: the executable and its
/// arguments as Settings stores them, before validation. Part of `MarkdownPreferences`, so
/// turning one on or off, or changing its executable or arguments, re-renders open documents
/// like any other Settings > Markdown change.
///
/// It is validated when a render builds its `PreprocessorConfiguration`, and the runner checks
/// the executable again just before it starts; an executable that went away is a failure the
/// window shows, never a silent unprocessed render.
struct CustomProgramPreference: Equatable, Sendable {
    /// An absolute path, as the Open panel returned it.
    var executablePath: String
    var arguments: [String] = []
}

/// The most recent run of a custom program in this session, for Settings' last-run line (#57).
/// Kept in memory only.
struct CustomProgramRun: Equatable, Sendable {
    /// The file name of the document it ran on.
    var documentName: String
    var date: Date
    /// Why it failed; `nil` when it succeeded.
    var error: PreprocessorError?
}

/// The reader's custom preprocessor (#57) or processor (#106) (Settings > Markdown), persisted
/// in `UserDefaults` under `kind`'s keys: whether it is on, the executable, and its arguments.
/// One instance per kind (`preprocessor`, `processor`); the two are independent.
///
/// It is off by default. Settings turns it on only after a warning (`CustomProgramModel`),
/// and nothing else turns it on: documents can't (frontmatter overrides never reach it, #54),
/// and there is no launch argument for it outside Debug UI tests (`UITestHooks`). The
/// executable is only ever set from an Open panel, so it is a file the reader picked.
///
/// Stored values are untrusted input: a path that isn't absolute reads as no executable, and
/// the program is on only with an executable (`preference`).
@MainActor
final class CustomProgramSettings {
    /// The app's preprocessor settings. UI tests and hosted unit tests keep them in memory,
    /// starting off (or, in a Debug UI test, at `-PeepUITestPreprocessor`'s executable), so
    /// neither reads nor writes the reader's preprocessor.
    static let preprocessor = app(.preprocessor, uiTestExecutable: UITestHooks.preprocessorExecutable)
    /// The app's processor settings, kept like `preprocessor` (`-PeepUITestProcessor`).
    static let processor = app(.processor, uiTestExecutable: UITestHooks.processorExecutable)

    private static func app(_ kind: CustomProgramKind, uiTestExecutable: String?) -> CustomProgramSettings {
        let settings = CustomProgramSettings(
            kind: kind, isPersistent: !UITestHooks.isUITesting && !AppDelegate.isHostingUnitTests)
        if let uiTestExecutable {
            settings.executablePath = uiTestExecutable
            settings.isEnabled = true
        }
        return settings
    }

    /// Posted (object: the settings) after any setting changes. Open documents render again.
    static let didChangeNotification = Notification.Name("PeepCustomProgramSettingsDidChange")
    /// Posted (object: the settings) after a run is recorded (`lastRun`). Only Settings follows
    /// it: a document finishing its run must not make other documents render again.
    static let lastRunDidChangeNotification = Notification.Name("PeepCustomProgramLastRunDidChange")

    /// A kind's `UserDefaults` keys. Each is absent at its default. The preprocessor's are the
    /// ones #57 shipped.
    struct Keys: Equatable {
        let enabled: String
        let executable: String
        let arguments: String

        static let preprocessor = Keys(
            enabled: "CustomPreprocessorEnabled", executable: "CustomPreprocessorExecutable",
            arguments: "CustomPreprocessorArguments")
        static let processor = Keys(
            enabled: "CustomProcessorEnabled", executable: "CustomProcessorExecutable",
            arguments: "CustomProcessorArguments")

        static func `for`(_ kind: CustomProgramKind) -> Keys {
            switch kind {
            case .preprocessor: .preprocessor
            case .processor: .processor
            }
        }

        var all: [String] { [enabled, executable, arguments] }
    }

    let kind: CustomProgramKind
    private let keys: Keys
    private let defaults: UserDefaults
    private let isPersistent: Bool
    private var memoryEnabled = false
    private var memoryExecutable: String?
    private var memoryArguments: [String] = []

    /// The last run in this session (never persisted).
    private(set) var lastRun: CustomProgramRun?

    init(
        kind: CustomProgramKind = .preprocessor, defaults: UserDefaults = .standard,
        isPersistent: Bool = !UITestHooks.isUITesting
    ) {
        self.kind = kind
        keys = Keys.for(kind)
        self.defaults = defaults
        self.isPersistent = isPersistent
    }

    /// What renders run: `nil` unless the program is on and has an executable.
    var preference: CustomProgramPreference? {
        guard isEnabled, let executablePath else {
            return nil
        }
        return CustomProgramPreference(executablePath: executablePath, arguments: arguments)
    }

    /// Whether the program is on. Reads `false` without an executable. Only Settings, after
    /// its warning, sets it.
    var isEnabled: Bool {
        get {
            guard executablePath != nil else {
                return false
            }
            return isPersistent ? defaults.bool(forKey: keys.enabled) : memoryEnabled
        }
        set {
            let enabled = newValue && executablePath != nil
            guard enabled != isEnabled else {
                return
            }
            if isPersistent {
                if enabled {
                    defaults.set(true, forKey: keys.enabled)
                } else {
                    defaults.removeObject(forKey: keys.enabled)
                }
            } else {
                memoryEnabled = enabled
            }
            didChange()
        }
    }

    /// The executable's absolute path, or `nil`. Setting a path that isn't absolute is ignored.
    var executablePath: String? {
        get {
            let path = isPersistent ? defaults.string(forKey: keys.executable) : memoryExecutable
            return path.flatMap(Self.absolutePath)
        }
        set {
            guard newValue == nil || newValue.flatMap(Self.absolutePath) != nil, newValue != executablePath else {
                return
            }
            if isPersistent {
                if let newValue {
                    defaults.set(newValue, forKey: keys.executable)
                } else {
                    defaults.removeObject(forKey: keys.executable)
                }
            } else {
                memoryExecutable = newValue
            }
            didChange()
        }
    }

    /// The arguments passed after the executable, verbatim.
    var arguments: [String] {
        get {
            isPersistent ? defaults.stringArray(forKey: keys.arguments) ?? [] : memoryArguments
        }
        set {
            guard newValue != arguments else {
                return
            }
            if isPersistent {
                if newValue.isEmpty {
                    defaults.removeObject(forKey: keys.arguments)
                } else {
                    defaults.set(newValue, forKey: keys.arguments)
                }
            } else {
                memoryArguments = newValue
            }
            didChange()
        }
    }

    /// Turns the program off and forgets the executable and arguments.
    func reset() {
        guard isEnabled || executablePath != nil || !arguments.isEmpty else {
            return
        }
        if isPersistent {
            for key in keys.all {
                defaults.removeObject(forKey: key)
            }
        } else {
            memoryEnabled = false
            memoryExecutable = nil
            memoryArguments = []
        }
        didChange()
    }

    /// Records a finished run (`MarkdownDocument.setContent(_:)`), for Settings' last-run line.
    func recordRun(_ run: CustomProgramRun) {
        lastRun = run
        NotificationCenter.default.post(name: Self.lastRunDidChangeNotification, object: self)
    }

    /// `path` if it is absolute and has no NUL character.
    private static func absolutePath(_ path: String) -> String? {
        path.hasPrefix("/") && !path.utf8.contains(0) ? path : nil
    }

    private func didChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
