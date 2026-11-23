import PeepCore
import WebKit

/// Open in Window on a diagram's controls (`App/Scripts/DiagramControls.js`): the page posts the
/// figure's index to `diagramWindow`, in the app's content world only; the coordinator reads that
/// figure's SVG back (`peepDiagramControls.markup`, the index passed as an argument) and hands it
/// to the window (`diagramWindowHandler`), which shows it in a `DiagramPanelController`.
extension WebViewCoordinator {
    /// One diagram to show in a window: its SVG markup and label, over the page's theme.
    struct DiagramWindowContent: Equatable {
        var svg: String
        var label: String
        var theme: Theme

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.svg == rhs.svg && lhs.label == rhs.label && lhs.theme.id == rhs.theme.id
        }
    }

    /// Reads the diagram at `index` and passes it to `diagramWindowHandler`. Does nothing when
    /// there is no such figure, or when the page changed before the read finished.
    func openDiagramWindow(at index: Int) async {
        guard index >= 0, hasLoadedPage else {
            return
        }
        let generation = pageGeneration
        let result = try? await webView.callAsyncJavaScript(
            "return peepDiagramControls.markup(index);", arguments: ["index": index], in: nil,
            contentWorld: AppScripts.world)
        guard generation == pageGeneration, let markup = result as? [String: Any],
            let svg = markup["svg"] as? String, !svg.isEmpty
        else {
            return
        }
        let label = markup["label"] as? String ?? "Diagram"
        diagramWindowHandler?(DiagramWindowContent(svg: svg, label: label, theme: theme))
    }
}

/// Receives `DiagramControls.js`'s Open in Window clicks: the figure's index, from the app's
/// content world only.
@MainActor
final class DiagramWindowMessageHandler: NSObject, WKScriptMessageHandler {
    /// The message handler name `DiagramControls.js` posts to.
    static let name = "diagramWindow"

    weak var coordinator: WebViewCoordinator?

    init(coordinator: WebViewCoordinator) {
        self.coordinator = coordinator
    }

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        guard message.frameInfo.isMainFrame, message.world.name == AppScripts.world.name,
            let number = message.body as? NSNumber, let coordinator
        else {
            return
        }
        let value = number.doubleValue
        guard value.isFinite, value >= 0, value <= Double(Int32.max), value.rounded() == value else {
            return
        }
        let index = Int(value)
        Task { await coordinator.openDiagramWindow(at: index) }
    }
}
