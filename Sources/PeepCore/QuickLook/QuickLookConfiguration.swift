import Foundation

/// What Quick Look renders with: the settings the app publishes into the shared App Group
/// container for its sandboxed Quick Look extension, which can't read the app's own defaults or
/// its Themes folder.
///
/// The extension treats it as untrusted input: an unreadable value is the default
/// (`init(data:)`), an unknown id falls back as everywhere else, and a custom theme's CSS must
/// pass `CustomThemeCSS` again (`themeRegistry`). Only presentation lives here; nothing in it can
/// turn on a custom preprocessor or processor, remote images, or local file reads.
public struct QuickLookConfiguration: Codable, Sendable, Equatable {
    /// The App Group suffix; the full identifier is the team id, a dot, then this.
    public static let appGroupSuffix = "now.peep"
    /// The Info.plist key (app and extension) holding the App Group identifier, set at build time
    /// from `$(TeamIdentifierPrefix)` (`PEEP_APP_GROUP` in `Config/Shared.xcconfig`).
    public static let appGroupInfoKey = "PeepAppGroup"

    /// The App Group identifier in `infoValue` when it is a team id prefix (ten uppercase letters
    /// or digits, then a dot) plus `appGroupSuffix`, else `nil`. A build without a team (ad hoc,
    /// unsigned) has only the suffix, and `UserDefaults(suiteName:)` would then write a plain
    /// preferences file rather than the group's, so it publishes and reads nothing.
    public static func appGroupIdentifier(infoValue: Any?) -> String? {
        guard let value = infoValue as? String, value.hasSuffix("." + appGroupSuffix) else {
            return nil
        }
        let team = value.dropLast(appGroupSuffix.count + 1)
        guard team.count == 10, team.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) || ("0"..."9").contains($0) })
        else {
            return nil
        }
        return value
    }

    /// The key the encoded configuration is stored under in the App Group's defaults.
    public static let defaultsKey = "QuickLookConfiguration"
    /// The built-in preprocessors Quick Look may run (Settings > Markdown's optional ones).
    public static let optionalPreprocessors: Set<MarkdownTransform> = [.wikiLinks]

    /// The theme id: the app's Quick Look theme, else its default theme. `nil` is the registry's
    /// default.
    public var themeID: String?
    /// The custom theme `themeID` names, when it names one, read from its file by the app.
    public var customTheme: QuickLookCustomTheme?
    /// Settings > Markdown's default flavor id. `nil` (or unknown) is GFM.
    public var flavorID: String?
    /// Settings > Markdown's frontmatter display (`FrontmatterDisplay.rawValue`).
    public var frontmatterDisplay: String?
    /// Settings > Markdown's built-in preprocessors (`MarkdownTransform.rawValue`).
    public var builtInPreprocessors: [String]
    /// Settings > Markdown's "Render diagrams" (M7). `nil` (a value published before it existed)
    /// is on, the default.
    public var diagrams: Bool?

    /// What Quick Look uses before the app has published anything (or without an App Group).
    public static let `default` = QuickLookConfiguration()

    public init(
        themeID: String? = nil, customTheme: QuickLookCustomTheme? = nil, flavorID: String? = nil,
        frontmatterDisplay: FrontmatterDisplay = .hidden, builtInPreprocessors: Set<MarkdownTransform> = [],
        rendersDiagrams: Bool = true
    ) {
        self.themeID = themeID
        self.customTheme = customTheme
        self.flavorID = flavorID
        self.frontmatterDisplay = frontmatterDisplay.rawValue
        self.builtInPreprocessors = MarkdownTransform.allCases.filter(builtInPreprocessors.contains).map(\.rawValue)
        diagrams = rendersDiagrams ? nil : false
    }

    /// Decodes `data` as `encoded()` wrote it; anything else (missing, malformed, wrong types)
    /// is `.default`.
    public init(data: Data?) {
        guard let data, data.count <= Self.maximumEncodedSize,
            let decoded = try? JSONDecoder().decode(Self.self, from: data)
        else {
            self = .default
            return
        }
        self = decoded
    }

    /// What the app published to the App Group named in `bundle`'s Info.plist, or `.default`
    /// without a group or a published value. The extension's one read.
    public static func published(bundle: Bundle = .main) -> QuickLookConfiguration {
        guard let group = appGroupIdentifier(infoValue: bundle.object(forInfoDictionaryKey: appGroupInfoKey)),
            let store = UserDefaults(suiteName: group)
        else {
            return .default
        }
        return QuickLookConfiguration(data: store.data(forKey: defaultsKey))
    }

    /// The JSON the app stores; `nil` only if encoding fails.
    public func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(self)
    }

    /// The largest stored value read: the largest custom theme file plus room for the rest.
    public static let maximumEncodedSize = CustomThemeFolder.maximumFileSize * 2 + 64 * 1024

    /// The flavor (unknown ids are GFM).
    public var flavor: Flavor {
        FlavorRegistry.bundled.flavor(id: flavorID)
    }

    /// The frontmatter display (unknown values hide it).
    public var frontmatter: FrontmatterDisplay {
        frontmatterDisplay.flatMap(FrontmatterDisplay.init(rawValue:)) ?? .hidden
    }

    /// Whether geojson and topojson blocks are drawn as maps (`RenderOptions.diagrams`).
    public var rendersDiagrams: Bool {
        diagrams ?? true
    }

    /// The built-in preprocessors, limited to `optionalPreprocessors`.
    public var preprocessors: Set<MarkdownTransform> {
        Set(builtInPreprocessors.compactMap(MarkdownTransform.init(rawValue:))).intersection(Self.optionalPreprocessors)
    }

    /// The bundled themes, plus `customTheme` when it is the theme `themeID` names and its CSS
    /// passes the custom theme checks (`CustomTheme.make`). A rejected theme is left out, so
    /// `themeID` falls back to the default.
    public var themeRegistry: ThemeRegistry {
        guard let customTheme, let theme = customTheme.theme, theme.id == themeID else {
            return .bundled
        }
        return ThemeRegistry.bundled.adding([theme])
    }
}

/// A custom theme file's name and text, as the app read it from the Themes folder.
public struct QuickLookCustomTheme: Codable, Sendable, Equatable {
    public var fileName: String
    public var css: String

    public init(fileName: String, css: String) {
        self.fileName = fileName
        self.css = css
    }

    /// The theme, checked as the app checks the file (`CustomTheme.make`), or `nil` if it fails:
    /// a file name that isn't a plain theme file name, CSS over the file size limit, or CSS the
    /// custom theme checks reject.
    public var theme: Theme? {
        guard CustomThemeFolder.isThemeFileName(fileName), !fileName.contains("/"),
            css.utf8.count <= CustomThemeFolder.maximumFileSize
        else {
            return nil
        }
        return try? CustomTheme.make(fileName: fileName, css: css)
    }
}
