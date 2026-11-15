import AppKit
import PeepCore
import QuickLookThumbnailing

/// Finder's thumbnail of a Markdown file (icon and gallery views): the start of the document
/// (`QuickLookThumbnail`) drawn on a page in the Quick Look theme's light background, with AppKit
/// text drawing (no web view). Sandboxed: it reads only the file. A file that isn't UTF-8 gets
/// the system's own thumbnail.
final class ThumbnailProvider: QLThumbnailProvider {
    /// A US Letter page's width over its height.
    private static let pageAspect: CGFloat = 8.5 / 11

    override func provideThumbnail(
        for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, (any Error)?) -> Void
    ) {
        let thumbnail: QuickLookThumbnail
        do {
            let data = try QuickLookPreview.readPrefix(
                of: request.fileURL, maximumBytes: QuickLookThumbnail.maximumSourceBytes)
            guard let made = QuickLookThumbnail.make(data: data, configuration: .published()) else {
                handler(nil, CocoaError(.fileReadInapplicableStringEncoding))
                return
            }
            thumbnail = made
        } catch {
            handler(nil, error)
            return
        }
        let maximum = request.maximumSize
        let height = min(maximum.height, maximum.width / Self.pageAspect)
        let size = CGSize(width: (height * Self.pageAspect).rounded(), height: height.rounded())
        let reply = QLThumbnailReply(contextSize: size) { () -> Bool in
            ThumbnailDrawing(thumbnail: thumbnail).draw(in: CGRect(origin: .zero, size: size))
            return true
        }
        handler(reply, nil)
    }
}
