import AppKit
import Testing

@testable import PeepApp

/// The Settings window's placement: a taller pane never puts its last rows under the Dock.
extension SettingsTests {
    @Test("a taller pane keeps the window above the Dock: it moves up, never past the top")
    func tallerPaneStaysOnScreen() async throws {
        let controller = SettingsWindowController(model: model(), savesFrame: false)
        defer { controller.close() }
        let window = try #require(controller.window)
        controller.show()
        let visible = try #require(window.screen?.visibleFrame)
        let tabs = try #require(window.contentViewController as? NSTabViewController)

        // General at the bottom of the visible frame, then the taller Markdown pane.
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: visible.minY))
        let generalHeight = window.frame.height
        tabs.selectedTabViewItemIndex = 1
        try await until("the Markdown pane's height") { window.frame.height > generalHeight }
        try await until("moved above the Dock") { window.frame.minY >= visible.minY }
        #expect(window.frame.maxY <= visible.maxY)
    }
}
