import AppKit
import PeepCore
import WebKit

/// The diagram window (Open in Window on a diagram's controls): one diagram, larger, in a
/// resizable panel like Quick Look's. One per document window (`DocumentWindowController
/// .diagramPanel`), reused for the next diagram and closed with its window.
///
/// Its web view is as locked down as a web view gets: JavaScript off, no user scripts, no
/// message handlers, no scheme handlers, and a navigation policy that allows only the page it
/// loads (`DiagramWindowPage`, which carries its own CSP). Pinch zooms; View > Zoom In, Zoom Out,
/// and Actual Size (the same shortcuts as a document) zoom it while it's key. Escape closes it.
@MainActor
final class DiagramPanelController: NSWindowController, WKNavigationDelegate {
    let webView: WKWebView
    /// The one load the navigation policy allows next (set just before `loadHTMLString`).
    private var allowsNextLoad = false
    /// The magnification steps View > Zoom walks through.
    static let magnifications: [CGFloat] = [0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4, 6, 8]

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.setAccessibilityIdentifier("diagram-window-web-view")
        self.webView = webView
        let panel = DiagramPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered,
            defer: true)
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 320, height: 240)
        panel.contentView = webView
        panel.setAccessibilityIdentifier("diagram-window")
        super.init(window: panel)
        webView.navigationDelegate = self
        panel.controller = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("DiagramPanelController is created in code")
    }

    /// Shows `content` (titled after the document), sized to most of the screen and centered on
    /// `parent` the first time it's shown, and makes the panel key.
    func show(_ content: WebViewCoordinator.DiagramWindowContent, documentTitle: String, over parent: NSWindow?) {
        guard let panel = window else {
            return
        }
        let title = documentTitle.isEmpty ? content.label : "\(documentTitle) — \(content.label)"
        panel.title = title
        panel.backgroundColor = .themeBackground(content.theme.background)
        webView.underPageBackgroundColor = .themeBackground(content.theme.background)
        webView.magnification = 1
        allowsNextLoad = true
        webView.loadHTMLString(
            DiagramWindowPage(title: title, svg: content.svg, theme: content.theme).html, baseURL: nil)
        if !panel.isVisible {
            place(panel, over: parent)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    private func place(_ panel: NSWindow, over parent: NSWindow?) {
        guard let screen = parent?.screen ?? NSScreen.main else {
            panel.center()
            return
        }
        let visible = screen.visibleFrame
        let size = NSSize(width: (visible.width * 0.8).rounded(), height: (visible.height * 0.8).rounded())
        let center =
            parent.map { NSPoint(x: $0.frame.midX, y: $0.frame.midY) }
            ?? NSPoint(x: visible.midX, y: visible.midY)
        var frame = NSRect(
            x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        panel.setFrame(frame, display: false)
    }

    // MARK: Zoom (View menu, while the panel is key)

    func zoomIn() {
        if let next = Self.magnifications.first(where: { $0 > webView.magnification + 0.001 }) {
            webView.magnification = next
        }
    }

    func zoomOut() {
        if let next = Self.magnifications.last(where: { $0 < webView.magnification - 0.001 }) {
            webView.magnification = next
        }
    }

    func resetZoom() {
        webView.magnification = 1
    }

    // MARK: WKNavigationDelegate

    /// Only the page `show` loads; every link or other navigation is cancelled.
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        let isOwnLoad =
            allowsNextLoad && navigationAction.targetFrame?.isMainFrame == true
            && navigationAction.navigationType == .other
        allowsNextLoad = false
        decisionHandler(isOwnLoad ? .allow : .cancel)
    }
}

/// The diagram window's panel: View > Zoom's actions (the document's selectors, so the same
/// menu items and shortcuts work while it's key) and Escape to close.
@MainActor
final class DiagramPanel: NSPanel {
    weak var controller: DiagramPanelController?

    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }

    @objc func zoomInDocument(_ sender: Any?) {
        controller?.zoomIn()
    }

    @objc func zoomOutDocument(_ sender: Any?) {
        controller?.zoomOut()
    }

    @objc func resetDocumentZoom(_ sender: Any?) {
        controller?.resetZoom()
    }
}
