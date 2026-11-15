/// What `HTMLRenderer` does with images whose source is remote (`RemoteImage`): Markdown
/// images and raw-HTML `<img>` (and `<picture><source srcset>`).
///
/// Blocking is a rendering decision, not only a CSP one, so a blocked image shows as a sized,
/// labeled placeholder (`RemoteImagePlaceholder`) instead of a broken image, and the renderer
/// can report what it blocked (`RenderedDocument.blockedRemoteImages`). The viewer's CSP
/// (`ContentSecurityPolicy.viewer`) still blocks every remote load on its own.
public enum RemoteImagePolicy: Sendable, Equatable {
    /// Leave remote images as `<img>`, as GitHub does. The default, so `peep --html` output stays
    /// GitHub-compatible.
    case keep
    /// Replace every remote image with a placeholder. The viewer's default.
    case block
    /// Keep `https:` images; replace every other remote image (cleartext `http:`,
    /// scheme-relative `//host`, other schemes) with a placeholder. The viewer after the user
    /// opts in to remote images for a window.
    case allowHTTPS
    /// Replace every image but `data:` URLs, local ones too (`RemoteImage(localSource:)`). Quick
    /// Look's preview: its sandbox can read the previewed file, never the images beside it.
    case blockAll

    /// Whether `image` becomes a placeholder.
    public func blocks(_ image: RemoteImage) -> Bool {
        switch self {
        case .keep: false
        case .block: !image.isLocal
        case .allowHTTPS: !image.isLocal && !image.isHTTPS
        case .blockAll: true
        }
    }

    /// The image `source` names when this policy replaces it with a placeholder, else `nil`.
    /// Local sources count only under `.blockAll`.
    func blockedImage(source: String) -> RemoteImage? {
        if let image = RemoteImage(source: source) {
            return blocks(image) ? image : nil
        }
        return self == .blockAll ? RemoteImage(localSource: source) : nil
    }
}

/// An image source that would be loaded from somewhere other than the document's own files:
/// any URL with a scheme other than `data:`, or a scheme-relative `//host/path`. Relative
/// paths are local (the app serves them through `DocumentURLScheme`).
public struct RemoteImage: Sendable, Equatable, Hashable {
    /// The source as written in the document (character references decoded, for raw HTML).
    public var url: String
    /// The lowercased host (with port, without user info), or empty when there is none.
    public var host: String
    /// The URL is `https:`, so it loads once the user opts in (`RemoteImagePolicy.allowHTTPS`).
    public var isHTTPS: Bool
    /// A local path (relative or root-relative), not a remote URL: only
    /// `RemoteImagePolicy.blockAll` replaces it. `host` is empty.
    public var isLocal = false

    /// Classifies `source`; `nil` when it is local (relative, or a `data:` URL).
    ///
    /// The source is cleaned the way the URL parser does: tab and newlines are removed
    /// everywhere, and leading and trailing controls and spaces are trimmed. A scheme must follow
    /// the URL grammar (`ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )`), so `a b:c` and `/x:y` are
    /// relative.
    public init?(source: String) {
        let cleaned = Self.cleaned(source)
        let scheme = Self.scheme(of: cleaned)
        let afterScheme: Substring
        if let scheme {
            if scheme == "data" {
                return nil
            }
            afterScheme = cleaned.dropFirst(scheme.count + 1)
        } else if Self.isSchemeRelative(cleaned) {
            afterScheme = Substring(cleaned)
        } else {
            return nil
        }
        url = source
        host = Self.host(after: afterScheme)
        isHTTPS = scheme == "https"
    }

    /// A local image: `source` has no scheme and isn't scheme-relative (so not `data:` either),
    /// and isn't blank. `nil` for anything else.
    init?(localSource source: String) {
        let cleaned = Self.cleaned(source)
        guard !cleaned.isEmpty, Self.scheme(of: cleaned) == nil, !Self.isSchemeRelative(cleaned) else {
            return nil
        }
        url = source
        host = ""
        isHTTPS = false
        isLocal = true
    }

    /// `source` cleaned the way the URL parser does: tab and newlines removed everywhere,
    /// leading and trailing controls and spaces trimmed.
    private static func cleaned(_ source: String) -> String {
        let isTrimmed: (Unicode.Scalar) -> Bool = { $0.value <= 0x20 }
        var scalars = source.unicodeScalars.filter { !["\t", "\n", "\r"].contains($0) }
        while let first = scalars.first, isTrimmed(first) {
            scalars.removeFirst()
        }
        while let last = scalars.last, isTrimmed(last) {
            scalars.removeLast()
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// The lowercased scheme of `url`, or `nil` when it has none (a relative URL).
    private static func scheme(of url: String) -> String? {
        guard let colon = url.firstIndex(of: ":") else {
            return nil
        }
        let candidate = url[..<colon]
        guard let first = candidate.unicodeScalars.first, first.isASCIILetter,
            candidate.unicodeScalars.allSatisfy({
                $0.isASCIILetter || $0.isASCIIDigit || "+-.".unicodeScalars.contains($0)
            })
        else {
            return nil
        }
        return candidate.lowercased()
    }

    /// `//host` (and the `\` spellings browsers treat the same way).
    private static func isSchemeRelative(_ url: String) -> Bool {
        let prefix = url.prefix(2)
        return prefix.count == 2 && prefix.allSatisfy { $0 == "/" || $0 == "\\" }
    }

    /// The authority's host and port: after any slashes, up to the path, query, or fragment,
    /// without user info. Browsers skip any number of slashes after `http:`/`https:`.
    private static func host(after rest: Substring) -> String {
        let authority = rest.drop { $0 == "/" || $0 == "\\" }.prefix { !"/\\?#".contains($0) }
        let host = authority.lastIndex(of: "@").map { authority[authority.index(after: $0)...] } ?? authority
        return host.lowercased()
    }
}

extension Unicode.Scalar {
    fileprivate var isASCIILetter: Bool {
        ("a"..."z").contains(self) || ("A"..."Z").contains(self)
    }

    fileprivate var isASCIIDigit: Bool {
        ("0"..."9").contains(self)
    }
}
