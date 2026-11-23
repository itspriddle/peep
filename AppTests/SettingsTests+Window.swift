import AppKit
import Testing

@testable import PeepApp

/// The Settings window: its panes, and its placement (a taller pane never puts its last rows
/// under the Dock).
extension SettingsTests {
    @Test(
        "the window: General, Markdown, Programs, Reading, and Quick Look panes, titled like the window, not restorable"
    )
    func window() throws {
        let controller = SettingsWindowController(model: model(), savesFrame: false)
        defer { controller.close() }
        let window = try #require(controller.window)
        #expect(window.identifier == SettingsWindowController.windowIdentifier)
        #expect(!window.isRestorable)
        let tabs = try #require(window.contentViewController as? NSTabViewController)
        #expect(tabs.tabStyle == .toolbar)
        #expect(tabs.tabViewItems.map(\.label) == ["General", "Markdown", "Programs", "Reading", "Quick Look"])

        controller.show()
        #expect(window.isVisible)
        #expect(window.title == "General")
    }

    @Test("no pane is taller than General, which already reaches the Dock on CI's screen")
    func panesFitCIScreen() async throws {
        let controller = SettingsWindowController(model: model(), savesFrame: false)
        defer { controller.close() }
        let window = try #require(controller.window)
        controller.show()
        let tabs = try #require(window.contentViewController as? NSTabViewController)
        let generalHeight = window.frame.height
        for (index, item) in tabs.tabViewItems.enumerated().dropFirst() {
            tabs.selectedTabViewItemIndex = index
            try await until("the \(item.label) pane") { window.title == item.label }
            try await settled(window)
            #expect(window.frame.height <= generalHeight, "\(item.label) is \(window.frame.height) points tall")
        }
    }

    @Test("a taller pane keeps the window above the Dock: it moves up, never past the top")
    func tallerPaneStaysOnScreen() async throws {
        let controller = SettingsWindowController(model: model(), savesFrame: false)
        defer { controller.close() }
        let window = try #require(controller.window)
        controller.show()
        let visible = try #require(window.screen?.visibleFrame)
        let tabs = try #require(window.contentViewController as? NSTabViewController)

        // The short Quick Look pane at the bottom of the visible frame, then the taller General.
        tabs.selectedTabViewItemIndex = tabs.tabViewItems.count - 1
        try await until("the Quick Look pane") { window.title == "Quick Look" }
        try await settled(window)
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: visible.minY))
        let shortHeight = window.frame.height
        tabs.selectedTabViewItemIndex = 0
        try await until("the General pane's height") { window.frame.height > shortHeight }
        try await until("moved above the Dock") { window.frame.minY >= visible.minY }
        #expect(window.frame.maxY <= visible.maxY)
    }

    /// Waits for a pane change's resize animation to end: the height holds for 200 ms.
    private func settled(_ window: NSWindow) async throws {
        var height = -1.0
        try await until("the window's height to settle") {
            let previous = height
            height = window.frame.height
            try await Task.sleep(for: .milliseconds(200))
            return previous == window.frame.height
        }
    }
}
