import AppKit
import SwiftUI

/// The Settings window (#36): App menu > Settings… (Command-comma, `SettingsMenu`).
///
/// One reusable window for the app's lifetime (`AppDelegate.showSettings(_:)`). The app
/// lifecycle is AppKit, so there is no SwiftUI `Settings` scene: an `NSTabViewController` in
/// toolbar style holds one pane per tab, each a SwiftUI form in an `NSHostingController`. A new
/// pane is one more `pane(...)` in `init`. The window remembers its position
/// (`frameAutosaveName`, not under UI tests) and isn't restored at launch. Switching to a
/// taller pane grows the window down from its top edge; `keepOnScreen()` then moves it up as
/// far as needed to keep the pane's last rows above the Dock.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    /// The window's accessibility identifier, for UI tests.
    static let windowIdentifier = NSUserInterfaceItemIdentifier("settings-window")
    static let frameAutosaveName = "PeepSettings"

    let model: SettingsModel

    init(model: SettingsModel, savesFrame: Bool = !UITestHooks.isUITesting) {
        self.model = model
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(
            Self.pane("General", symbol: "gearshape", identifier: "general", GeneralSettingsView(model: model)))
        tabs.addTabViewItem(
            Self.pane("Markdown", symbol: "doc.text", identifier: "markdown", MarkdownSettingsView(model: model)))
        tabs.addTabViewItem(
            Self.pane("Programs", symbol: "terminal", identifier: "programs", ProgramsSettingsView(model: model)))
        tabs.addTabViewItem(
            Self.pane("Reading", symbol: "book", identifier: "reading", ReadingSettingsView(model: model)))
        tabs.addTabViewItem(
            Self.pane("Quick Look", symbol: "eye", identifier: "quicklook", QuickLookSettingsView(model: model)))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.identifier = Self.windowIdentifier
        window.isRestorable = false
        window.collectionBehavior.insert(.fullScreenNone)
        super.init(window: window)
        window.delegate = self
        if !savesFrame || !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        if savesFrame {
            window.setFrameAutosaveName(Self.frameAutosaveName)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsWindowController is created in code")
    }

    /// A tab whose content is `view`, sized to fit it.
    private static func pane(
        _ label: String, symbol: String, identifier: String, _ view: some View
    ) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        // The tab view controller shows the selected pane's title as the window's.
        controller.title = label
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.identifier = identifier
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }

    /// Shows the window in front, with current values.
    func show() {
        model.refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Moves the window up when its bottom is below the screen's visible frame (under the Dock
    /// or off the screen), never past the visible frame's top.
    func keepOnScreen() {
        guard let window, let visible = (window.screen ?? NSScreen.main)?.visibleFrame,
            window.frame.minY < visible.minY
        else {
            return
        }
        let origin = NSPoint(x: window.frame.minX, y: min(visible.minY, visible.maxY - window.frame.height))
        window.setFrameOrigin(origin)
    }

    // MARK: NSWindowDelegate

    /// A pane change resizes the window from its top edge.
    func windowDidResize(_ notification: Notification) {
        keepOnScreen()
    }

    /// The outline preference and the default viewer post no change notifications; read them
    /// again whenever the reader comes back to the window.
    func windowDidBecomeKey(_ notification: Notification) {
        model.refresh()
    }
}
