import Foundation
import PeepCore
import Testing
import WebKit

@testable import PeepApp

/// Color swatches in a document window: off by default, Settings > Markdown turns them on in
/// place, and the page's CSP and base layer let the inline color through as a visible dot.
@MainActor
@Suite("Color swatches in the app", .serialized, .timeLimit(.minutes(1)))
final class ColorSwatchWindowTests: DocumentWindowTestCase {
    /// Each swatch's computed background color and size, in document order.
    func swatches(in controller: DocumentWindowController) async throws -> [String] {
        try await controller.coordinator.webView.callAsyncJavaScript(
            """
            return [...document.querySelectorAll('code > .peep-color-swatch')].map((swatch) => {
              const style = getComputedStyle(swatch);
              return `${style.backgroundColor} ${style.width}x${style.height}`;
            });
            """, arguments: [:], in: nil, contentWorld: AppScripts.world) as? [String] ?? []
    }

    @Test("off by default; Settings turns them on in place, drawn in the code span's color")
    func settingsTurnsThemOn() async throws {
        defer { closeAll() }
        let store = MarkdownSettings(defaults: defaults, isPersistent: true)
        let (_, controller) = try await open(
            "`#0969DA` `rgba(9, 105, 218, 0.5)` `hsl(0, 100%, 50%)` `#nope`", markdownSettings: store)
        #expect(try await swatches(in: controller).isEmpty)

        store.builtInPreprocessors = [.colorSwatches]
        try await until("swatches drawn") { try await !swatches(in: controller).isEmpty }
        #expect(
            try await swatches(in: controller) == [
                "rgb(9, 105, 218) 8pxx8px",
                "rgba(9, 105, 218, 0.5) 8pxx8px",
                "rgb(255, 0, 0) 8pxx8px",
            ])
    }
}
