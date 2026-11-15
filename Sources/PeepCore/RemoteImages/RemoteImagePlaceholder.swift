import Foundation

/// The markup that replaces a blocked remote image: a labeled box showing the image's alt text
/// and host, sized like the image when the document gives a size (raw HTML `width`/`height`).
///
///     <span class="remote-image" role="img" aria-label="Blocked remote image: Build (img.shields.io)"
///      title="https://img.shields.io/badge.svg"><span class="remote-image-alt">Build</span>
///      <span class="remote-image-host">img.shields.io</span></span>
///
/// A local image (`RemoteImage.isLocal`, Quick Look's `RemoteImagePolicy.blockAll`) is labeled
/// "Image not shown" and shows its file name where a remote one shows its host.
///
/// It has no URL-valued attribute, so it loads nothing. The theme styles the classes. A URL
/// ending in GitHub's `#gh-dark-mode-only` or `#gh-light-mode-only` adds that fragment as a
/// class, so the theme shows the placeholder only in that appearance, like the image itself.
enum RemoteImagePlaceholder {
    /// `escapedAlt` is the alt text already escaped for a double-quoted attribute (and so for
    /// element content too); `width` and `height` are raw HTML attribute values, used only when
    /// they are plain lengths (`Length`).
    static func html(escapedAlt: String, image: RemoteImage, width: String? = nil, height: String? = nil) -> String {
        let label = escapedAlt.isEmpty ? "Image" : escapedAlt
        let host = HTMLDocument.escape(image.isLocal ? fileName(of: image.url) : image.host)
        let modeClass = ColorModeImage(source: image.url).map { " " + $0.fragment } ?? ""
        let prefix = image.isLocal ? "Image not shown" : "Blocked remote image"
        var html =
            "<span class=\"remote-image\(modeClass)\" role=\"img\" aria-label=\"\(prefix): \(label)"
        if !host.isEmpty {
            html += " (\(host))"
        }
        html += "\" title=\"\(HTMLDocument.escape(image.url))\""
        let style = [("width", width), ("height", height)].compactMap { property, value in
            value.flatMap(Length.init).map { "\(property): \($0.css)" }
        }
        if !style.isEmpty {
            html += " style=\"\(style.joined(separator: "; "))\""
        }
        html += "><span class=\"remote-image-alt\">\(label)</span>"
        if !host.isEmpty {
            html += "<span class=\"remote-image-host\">\(host)</span>"
        }
        return html + "</span>"
    }

    /// The last path component of a local source, without its query or fragment.
    private static func fileName(of source: String) -> String {
        let path = source.prefix { $0 != "?" && $0 != "#" }
        let name = path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        return name.removingPercentEncoding ?? name
    }

    /// A raw HTML `width`/`height` value the placeholder can copy: digits with an optional `px`,
    /// or digits and `%`. Anything else is ignored, so nothing but a number reaches the style.
    struct Length: Equatable {
        var value: Int
        var isPercent: Bool

        static let maximumPixels = 10_000

        init?(_ attribute: String) {
            var text = Substring(attribute.trimmingCharacters(in: .whitespacesAndNewlines))
            isPercent = text.hasSuffix("%")
            if isPercent {
                text = text.dropLast()
            } else if text.lowercased().hasSuffix("px") {
                text = text.dropLast(2)
            }
            guard !text.isEmpty, text.count <= 6, text.allSatisfy({ ("0"..."9").contains($0) }), let value = Int(text),
                value > 0
            else {
                return nil
            }
            self.value = isPercent ? min(value, 100) : min(value, Self.maximumPixels)
        }

        var css: String {
            isPercent ? "\(value)%" : "\(value)px"
        }
    }
}
