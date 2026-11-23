import AppKit
import Foundation
import Testing

@testable import PeepApp

/// "Bring the window to the front when a file is saved" (`RaiseOnChangeSettings`): a live reload
/// that changed the text brings the document's window forward (`MarkdownDocument.raiseTarget`).
@MainActor
@Suite("Raise on change", .serialized, .timeLimit(.minutes(1)))
final class RaiseOnChangeTests: DocumentWindowTestCase {
    func raiseSettings(enabled: Bool = true) -> RaiseOnChangeSettings {
        let settings = RaiseOnChangeSettings(defaults: defaults, isPersistent: true)
        settings.isEnabled = enabled
        return settings
    }

    /// Opens `source` as `name` with its window on screen, live reload on, following `settings`.
    func openShown(
        _ source: String, name: String, settings: RaiseOnChangeSettings
    ) async throws -> (MarkdownDocument, DocumentWindowController) {
        let (document, controller) = try await open(source, name: name)
        document.raiseOnChangeSettings = settings
        document.showWindows()
        document.startLiveReload()
        return (document, controller)
    }

    /// Writes `source` to the document's file and waits for the reload to land.
    func save(_ source: String, to document: MarkdownDocument) async throws {
        try Data(source.utf8).write(to: try #require(document.fileURL))
        try await until("the reload") { document.content?.source == source }
    }

    /// Whether `window` is in front of `other` among the app's windows.
    func isInFront(_ window: NSWindow?, of other: NSWindow?) -> Bool {
        let order = NSApp.orderedWindows
        guard let window, let other, let front = order.firstIndex(of: window), let back = order.firstIndex(of: other)
        else {
            return false
        }
        return front < back
    }

    @Test("the setting is off by default, persists, reads bad values as off, and posts changes")
    func settingPersists() {
        let settings = raiseSettings(enabled: false)
        #expect(!settings.isEnabled)
        var posts = 0
        let token = NotificationCenter.default.addObserver(
            forName: RaiseOnChangeSettings.didChangeNotification, object: settings, queue: nil
        ) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        settings.isEnabled = true
        settings.isEnabled = true
        #expect(posts == 1, "setting the same value posts nothing")
        #expect(defaults.bool(forKey: RaiseOnChangeSettings.key))
        settings.isEnabled = false
        #expect(defaults.object(forKey: RaiseOnChangeSettings.key) == nil, "off removes the key")
        defaults.set("yes", forKey: RaiseOnChangeSettings.key)
        #expect(!settings.isEnabled)
    }

    @Test("on, a save that changes the text brings the window in front of another")
    func raisesOnChange() async throws {
        defer { closeAll() }
        let settings = raiseSettings()
        let (document, controller) = try await openShown("# First\n", name: "first.md", settings: settings)
        let (_, other) = try await openShown("# Other\n", name: "other.md", settings: settings)
        other.window?.makeKeyAndOrderFront(nil)
        #expect(isInFront(other.window, of: controller.window))

        try await save("# Changed\n", to: document)
        #expect(document.raiseTarget === controller)
        try await until("the window in front") { isInFront(controller.window, of: other.window) }
    }

    @Test("off, a save leaves the window where it is")
    func offLeavesWindow() async throws {
        defer { closeAll() }
        // One store: stores over the same defaults share the setting.
        let settings = raiseSettings(enabled: false)
        let (document, controller) = try await openShown("# First\n", name: "first.md", settings: settings)
        let (_, other) = try await openShown("# Other\n", name: "other.md", settings: settings)
        other.window?.makeKeyAndOrderFront(nil)

        try await save("# Changed\n", to: document)
        try await until("the title") { controller.window?.title == "Changed" }
        #expect(document.raiseTarget == nil)
        #expect(isInFront(other.window, of: controller.window))
    }

    @Test("a move with the same text, or a Settings re-render, raises nothing")
    func sameTextRaisesNothing() async throws {
        defer { closeAll() }
        let (document, controller) = try await openShown("# First\n", name: "first.md", settings: raiseSettings())
        try await save("# Changed\n", to: document)
        #expect(document.raiseTarget === controller)

        let moved = folder.appending(path: "moved.md")
        try FileManager.default.moveItem(at: try #require(document.fileURL), to: moved)
        try await until("the move") { document.fileURL?.lastPathComponent == "moved.md" }
        try await until("the forced reload") { document.raiseTarget == nil }

        try await save("# Again\n", to: document)
        #expect(document.raiseTarget === controller)
        let content = try #require(document.content)
        document.setContent(content)
        #expect(document.raiseTarget == nil, "any other content change clears it")
    }

    @Test("a minimized window is restored")
    func restoresMinimized() async throws {
        defer { closeAll() }
        let (document, controller) = try await openShown("# First\n", name: "first.md", settings: raiseSettings())
        let window = try #require(controller.window)
        window.miniaturize(nil)
        try await until("minimized") { window.isMiniaturized }

        try await save("# Changed\n", to: document)
        try await until("restored") { !window.isMiniaturized && window.isVisible }
    }
}
