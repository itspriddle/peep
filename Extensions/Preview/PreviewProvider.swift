import Foundation
import PeepCore
import QuickLookUI
import UniformTypeIdentifiers

/// Quick Look's preview of a Markdown file (space bar, Finder's preview pane): Peep's rendered page
/// as HTML (`QuickLookPreview`), which Quick Look shows itself, with what the app published
/// (`QuickLookConfiguration.published()`). Sandboxed: it reads only the previewed file.
///
/// A file that isn't UTF-8 throws, and Quick Look falls back to its own plain text preview.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let data = try QuickLookPreview.readPrefix(of: url)
        let html = try QuickLookPreview.html(
            data: data, fileName: url.lastPathComponent, configuration: .published())
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 800, height: 1000)) { reply in
            reply.stringEncoding = .utf8
            return Data(html.utf8)
        }
        return reply
    }
}
