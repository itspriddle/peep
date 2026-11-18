import AppKit
import PeepCore
import WebKit

/// Change highlights: while Settings > Reading's "Highlight changes when a file is saved" is on
/// (`ChangeHighlightsSettings`, every window), each live reload marks the blocks it changed
/// (`MarkdownDocument.contentChanges`, `App/Scripts/ChangeMarks.js`). Marks fade once seen; the
/// status bar counts those out of view (`ChangesItem`), and clicking it scrolls to the next.
/// "Scroll to the first change" (`ChangeHighlightsSettings.scrollsToChanges`) scrolls there
/// after the reload instead, when no change is in view.
/// Any other content change (a Settings re-render, opting in to remote images) clears them.
extension DocumentWindowController {
    /// Listens for the page's off-screen counts and follows the setting. Called once from `init`.
    func installChangeHighlights() {
        coordinator.webView.configuration.userContentController.add(
            ChangeMarksMessageHandler(windowController: self), contentWorld: AppScripts.world,
            name: ChangeMarksMessageHandler.name)
        NotificationCenter.default.addObserver(
            self, selector: #selector(changeHighlightsSettingsDidChange(_:)),
            name: ChangeHighlightsSettings.didChangeNotification, object: changeHighlightsSettings)
    }

    /// Turning the setting off clears this window's marks; on applies from the next reload.
    @objc private func changeHighlightsSettingsDidChange(_ notification: Notification) {
        guard !changeHighlightsSettings.isEnabled else {
            return
        }
        statusBar.offScreenChanges = nil
        Task { [coordinator] in
            try? await coordinator.clearChanges()
        }
    }

    /// Marks `changes` (the document's `contentChanges` when the page was shown) in the page,
    /// replacing earlier marks, then, with "Scroll to the first change" on, scrolls to the first
    /// one when none is in view. Called after every load or swap while the setting is on (after
    /// the reading position is restored, so the scroll wins).
    func showChanges(_ changes: SourceChanges?) async {
        guard changeHighlightsSettings.isEnabled else {
            return
        }
        // The page reports new counts as it places the marks.
        statusBar.offScreenChanges = nil
        try? await coordinator.markChanges(changes)
        if let changes, !changes.isEmpty, changeHighlightsSettings.scrollsOnChange {
            try? await coordinator.scrollToFirstChange()
        }
    }

    /// A count report from `ChangeMarks.js`.
    func offScreenChangesDidChange(_ changes: OffScreenChanges) {
        statusBar.offScreenChanges = changes.total > 0 && changeHighlightsSettings.isEnabled ? changes : nil
    }

    /// The status bar's changes item: scrolls to the next change out of view.
    @objc func scrollToNextChange(_ sender: Any?) {
        Task { [coordinator] in
            try? await coordinator.scrollToNextChange()
        }
    }
}

/// Receives `ChangeMarks.js`'s off-screen counts (`{ above, below }`), from the app's content
/// world and main frame only. The body is untrusted input: anything but two small non-negative
/// integers is ignored.
final class ChangeMarksMessageHandler: NSObject, WKScriptMessageHandler {
    /// The message handler name `ChangeMarks.js` posts to.
    static let name = "changeMarks"

    /// More marks than this in one report is not something the page sends.
    nonisolated static let maximumCount = 1_000_000

    private weak var windowController: DocumentWindowController?

    init(windowController: DocumentWindowController) {
        self.windowController = windowController
    }

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        guard message.frameInfo.isMainFrame, message.world.name == AppScripts.world.name,
            let changes = Self.offScreenChanges(from: message.body)
        else {
            return
        }
        windowController?.offScreenChangesDidChange(changes)
    }

    /// The counts in a message body, or nil when it isn't `{ above, below }` with valid counts.
    nonisolated static func offScreenChanges(from body: Any) -> OffScreenChanges? {
        guard let body = body as? [String: Any], let above = count(body["above"]), let below = count(body["below"])
        else {
            return nil
        }
        return OffScreenChanges(above: above, below: below)
    }

    nonisolated private static func count(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else {
            return nil
        }
        let double = number.doubleValue
        guard double.isFinite, double >= 0, double <= Double(maximumCount), double.rounded() == double else {
            return nil
        }
        return Int(double)
    }
}
