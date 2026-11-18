import AppKit
import PeepCore
import WebKit

/// Mermaid diagrams on a loaded page (#117, `DiagramScripts`, `App/Scripts/MermaidDiagrams.js`).
///
/// Lazy: a page without mermaid blocks to draw (`RenderedPage.hasMermaidBlocks`, which is false
/// when Settings > Markdown > Render diagrams is off) never gets mermaid, and nothing here runs
/// for it. For one that has them, after the load mermaid is evaluated once in the diagrams
/// world, then the blocks are drawn; a live reload or Settings swap reuses it and draws the new
/// blocks (turning Render diagrams off re-renders the document, so the swap brings the code
/// blocks back). A theme or appearance change of another darkness draws them again in
/// mermaid's dark or default colors. Each draw keeps the reading position (a diagram is rarely
/// as tall as its code). The work runs in the background, one step at a time
/// (`pendingDiagramRender`); a failure leaves the code blocks, never fails a load.
extension WebViewCoordinator {
    /// What the loaded page holds. Reset by every full load.
    struct DiagramPageState: Equatable {
        /// The page has mermaid blocks to draw.
        var hasMermaidBlocks = false
        /// The `pageGeneration` whose page mermaid was evaluated in, if any.
        var installedGeneration: Int?
        /// Whether the page's diagrams were last drawn dark; nil when they haven't been drawn.
        var renderedDark: Bool?
    }

    /// Whether diagrams should be drawn dark: the shown theme's background for this web view's
    /// appearance is dark (`ThemeColor.isDark`), like the page's own colors.
    var diagramsAreDark: Bool {
        let isDarkAppearance = webView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return (isDarkAppearance ? theme.background.dark : theme.background.light).isDark
    }

    /// After a swap (`updateContent`, `replaceContent`): the new body's blocks aren't drawn yet.
    func contentDidSwap(to page: RenderedPage) {
        diagrams.hasMermaidBlocks = page.hasMermaidBlocks
        diagrams.renderedDark = nil
        scheduleDiagramRender()
    }

    /// Draws the page's diagrams, after any diagram work already started, unless they are
    /// already drawn in the current colors. Does nothing (and starts no task) for a page without
    /// mermaid blocks to draw.
    func scheduleDiagramRender() {
        guard hasLoadedPage, diagrams.hasMermaidBlocks, diagrams.renderedDark != diagramsAreDark else {
            return
        }
        let previous = pendingDiagramRender
        pendingDiagramRender = Task { [weak self] in
            await previous?.value
            // A failed draw leaves the code blocks; a newer load or swap starts its own.
            try? await self?.renderDiagrams()
        }
    }

    /// Evaluates mermaid in the loaded page if it isn't there yet, then draws every block.
    private func renderDiagrams() async throws {
        let dark = diagramsAreDark
        guard hasLoadedPage, diagrams.hasMermaidBlocks, diagrams.renderedDark != dark else {
            return
        }
        let generation = pageGeneration
        try await installDiagramScripts()
        guard generation == pageGeneration else {
            return
        }
        diagrams.renderedDark = dark
        let position = try? await readingPosition()
        _ = try await webView.callAsyncJavaScript(
            "return await peepDiagrams.render(dark);", arguments: ["dark": dark], in: nil,
            contentWorld: DiagramScripts.world)
        if let position, generation == pageGeneration {
            try await restore(position)
        }
    }

    /// Evaluates mermaid and `MermaidDiagrams.js` in the diagrams world of the loaded page, once
    /// per page. The source is read off the main actor the first time.
    private func installDiagramScripts() async throws {
        let generation = pageGeneration
        guard diagrams.installedGeneration != generation else {
            return
        }
        let source = await Task.detached(priority: .userInitiated) { DiagramScripts.source }.value
        guard generation == pageGeneration, hasLoadedPage else {
            return
        }
        _ = try await webView.evaluateJavaScript(source, in: nil, contentWorld: DiagramScripts.world)
        if generation == pageGeneration {
            diagrams.installedGeneration = generation
        }
    }
}
