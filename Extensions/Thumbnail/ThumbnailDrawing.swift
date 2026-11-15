import AppKit
import PeepCore

/// Draws a `QuickLookThumbnail` into the current graphics context: a page laid out at
/// `pageWidth` points and scaled to fit, so text sizes look the same at every thumbnail size.
struct ThumbnailDrawing {
    /// The width the page is laid out at, in points, before scaling.
    static let pageWidth: CGFloat = 480
    private static let margin: CGFloat = 36

    let thumbnail: QuickLookThumbnail

    func draw(in rect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        let background = thumbnail.background.light
        NSColor(theme: background).setFill()
        rect.fill()

        let scale = rect.width / Self.pageWidth
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        let page = CGRect(x: 0, y: 0, width: Self.pageWidth, height: rect.height / scale)
        let text = attributedText(dark: background.isDark)
        text.draw(
            with: page.insetBy(dx: Self.margin, dy: Self.margin),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        context.restoreGState()
    }

    private func attributedText(dark: Bool) -> NSAttributedString {
        let ink = dark ? NSColor(white: 0.9, alpha: 1) : NSColor(white: 0.14, alpha: 1)
        let muted = ink.withAlphaComponent(0.65)
        let result = NSMutableAttributedString()
        for block in thumbnail.blocks {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = 10
            style.lineBreakMode = .byWordWrapping
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: ink, .paragraphStyle: style]
            let text: String
            switch block {
            case .heading(let level, let heading):
                let sizes: [CGFloat] = [30, 24, 20, 18, 16, 15]
                attributes[.font] = NSFont.boldSystemFont(ofSize: sizes[min(max(level, 1), 6) - 1])
                style.paragraphSpacing = 12
                text = heading
            case .paragraph(let paragraph):
                attributes[.font] = NSFont.systemFont(ofSize: 15)
                text = paragraph
            case .listItem(let item):
                attributes[.font] = NSFont.systemFont(ofSize: 15)
                style.headIndent = 18
                style.firstLineHeadIndent = 0
                style.paragraphSpacing = 4
                text = "•  " + item
            case .quote(let quote):
                attributes[.font] = NSFont.systemFont(ofSize: 15)
                attributes[.foregroundColor] = muted
                style.headIndent = 16
                style.firstLineHeadIndent = 16
                text = quote
            case .code(let code):
                attributes[.font] = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                attributes[.foregroundColor] = muted
                text = code.hasSuffix("\n") ? String(code.dropLast()) : code
            case .rule:
                attributes[.font] = NSFont.systemFont(ofSize: 15)
                attributes[.foregroundColor] = muted
                text = "———"
            }
            result.append(NSAttributedString(string: text + "\n", attributes: attributes))
        }
        return result
    }
}

extension NSColor {
    /// A theme color, in sRGB.
    convenience init(theme color: ThemeColor) {
        self.init(
            srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255,
            alpha: 1)
    }
}
