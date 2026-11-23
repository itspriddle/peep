import Foundation
import WebKit

/// The diagrams content world (#117): the vendored mermaid (`Vendor/mermaid/mermaid.min.js`,
/// `make vendor-mermaid`) and `App/Scripts/MermaidDiagrams.js`, evaluated together in a page
/// only when it has mermaid blocks (`WebViewCoordinator+Diagrams.swift`).
///
/// Policy (VISION, security model): page JavaScript stays disabled and the page CSP is
/// unchanged (no `unsafe-eval`). mermaid runs in `world`, an isolated `WKContentWorld` of its
/// own: it shares the DOM with the page but no globals with the page or with `AppScripts.world`,
/// and has no message handlers, so a bug in mermaid can't reach the app's bridge or post to
/// the app. Values reach it only as `callAsyncJavaScript` arguments.
enum DiagramScripts {
    /// The isolated world mermaid runs in. Never add a message handler to it.
    @MainActor static let world = WKContentWorld.world(name: "peep-diagrams")

    /// mermaid, then `MermaidDiagrams.js` (which defines `peepDiagrams`), as one script. Read
    /// from the bundle on first use (about 5.5 MB), off the main actor
    /// (`WebViewCoordinator.installDiagramScripts()`). A missing file is a packaging bug, so it
    /// traps rather than shipping a viewer that silently never draws diagrams.
    static let source: String = {
        guard
            let mermaidURL = Bundle.main.url(
                forResource: "mermaid.min", withExtension: "js", subdirectory: "Vendor/mermaid"),
            let mermaid = try? String(contentsOf: mermaidURL, encoding: .utf8),
            let scriptURL = Bundle.main.url(forResource: "MermaidDiagrams", withExtension: "js"),
            let script = try? String(contentsOf: scriptURL, encoding: .utf8)
        else {
            preconditionFailure("Vendor/mermaid/mermaid.min.js or MermaidDiagrams.js is missing from the app bundle")
        }
        // `;` and a newline end mermaid's last statement whatever it is; `true` is the result
        // (evaluateJavaScript must return a value it can serialize).
        return mermaid + "\n;\n" + script + "\n;true;\n"
    }()
}
