import AppKit
import PeepCore

/// Open in Window on a diagram's controls (`WebViewCoordinator+DiagramWindow.swift`): shows the
/// diagram in this window's `DiagramPanelController`, made on first use and closed with the
/// window's content.
extension DocumentWindowController {
    /// Routes the coordinator's Open in Window requests to this window. Called once from `init`.
    func installDiagramWindow() {
        coordinator.diagramWindowHandler = { [weak self] content in
            self?.showDiagramWindow(content)
        }
    }

    func showDiagramWindow(_ content: WebViewCoordinator.DiagramWindowContent) {
        let panel = diagramPanel ?? DiagramPanelController()
        diagramPanel = panel
        panel.show(content, documentTitle: window?.title ?? "", over: window)
    }

    /// Closes the diagram window, if one is open (the document window is closing).
    func closeDiagramWindow() {
        diagramPanel?.close()
        diagramPanel = nil
    }
}
