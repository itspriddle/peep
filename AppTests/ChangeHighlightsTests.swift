import AppKit
import PeepCore
import Testing
import WebKit

@testable import PeepApp

/// "Highlight changes when a file is saved" (`ChangeHighlightsSettings`): live reloads work out
/// what changed (`MarkdownDocument.contentChanges`), the page marks it (`ChangeMarks.js`), and
/// the status bar counts the marks out of view.
@MainActor
@Suite("Change highlights", .serialized, .timeLimit(.minutes(1)))
final class ChangeHighlightsTests: DocumentWindowTestCase {
    static let shortSource = "# Title\n\nFirst paragraph.\n\nSecond paragraph.\n\nThird paragraph.\n"
    /// 200 one-line paragraphs: paragraph N is on line 2N - 1.
    static let longSource = (1...200).map { "Paragraph \($0)." }.joined(separator: "\n\n") + "\n"

    func highlightSettings(enabled: Bool = true, scrolls: Bool = false) -> ChangeHighlightsSettings {
        let settings = ChangeHighlightsSettings(defaults: defaults, isPersistent: true)
        settings.isEnabled = enabled
        settings.scrollsToChanges = scrolls
        return settings
    }

    func scrollY(_ controller: DocumentWindowController) async throws -> Double {
        (try await evaluate("return window.scrollY;", in: controller) as? NSNumber)?.doubleValue ?? 0
    }

    /// Whether the paragraph containing `text` is wholly inside the viewport.
    func isInView(_ text: String, in controller: DocumentWindowController) async throws -> Bool {
        let script = """
            const block = [...document.querySelectorAll('article p')].find((p) => p.textContent.includes(text));
            if (!block) { return false; }
            const rect = block.getBoundingClientRect();
            return rect.top >= 0 && rect.bottom <= window.innerHeight;
            """
        let result = try await controller.coordinator.webView.callAsyncJavaScript(
            script, arguments: ["text": text], in: nil, contentWorld: AppScripts.world)
        return (result as? NSNumber)?.boolValue == true
    }

    func evaluate(_ script: String, in controller: DocumentWindowController) async throws -> Any? {
        try await controller.coordinator.webView.callAsyncJavaScript(
            script, arguments: [:], in: nil, contentWorld: AppScripts.world)
    }

    /// The kinds of the bars in the page, in order.
    func barKinds(in controller: DocumentWindowController) async throws -> [String] {
        let result = try await evaluate(
            """
            return [...document.querySelectorAll('[data-peep-change]')]
              .map((bar) => bar.getAttribute('data-peep-change'));
            """,
            in: controller)
        return result as? [String] ?? []
    }

    /// Whether the first bar's top is level with the top of the paragraph containing `text`.
    func firstBarIsBeside(_ text: String, in controller: DocumentWindowController) async throws -> Bool {
        let script = """
            const bar = document.querySelector('[data-peep-change]');
            const block = [...document.querySelectorAll('article p')].find((p) => p.textContent.includes(text));
            if (!bar || !block) { return false; }
            return Math.abs(bar.getBoundingClientRect().top - block.getBoundingClientRect().top) < 1;
            """
        let result = try await controller.coordinator.webView.callAsyncJavaScript(
            script, arguments: ["text": text], in: nil, contentWorld: AppScripts.world)
        return (result as? NSNumber)?.boolValue == true
    }

    /// Writes `source` to the document's file and waits for the reload to land.
    func save(_ source: String, to document: MarkdownDocument) async throws {
        try Data(source.utf8).write(to: try #require(document.fileURL))
        try await until("the reload") { document.content?.source == source }
    }

    @Test("the setting is off by default, persists, reads bad values as off, and posts changes")
    func settingsPersist() {
        let settings = highlightSettings(enabled: false)
        #expect(!settings.isEnabled)
        var posts = 0
        let token = NotificationCenter.default.addObserver(
            forName: ChangeHighlightsSettings.didChangeNotification, object: settings, queue: nil
        ) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        settings.isEnabled = true
        settings.isEnabled = true
        #expect(posts == 1, "setting the same value posts nothing")
        #expect(defaults.bool(forKey: ChangeHighlightsSettings.key))
        settings.isEnabled = false
        #expect(defaults.object(forKey: ChangeHighlightsSettings.key) == nil, "off removes the key")
        defaults.set("yes", forKey: ChangeHighlightsSettings.key)
        #expect(!settings.isEnabled)
    }

    @Test("scrolling to changes is off by default, persists, and applies only with highlights on")
    func scrollSettingPersists() {
        let settings = highlightSettings(enabled: false)
        #expect(!settings.scrollsToChanges)
        var posts = 0
        let token = NotificationCenter.default.addObserver(
            forName: ChangeHighlightsSettings.didChangeNotification, object: settings, queue: nil
        ) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        settings.scrollsToChanges = true
        settings.scrollsToChanges = true
        #expect(posts == 1, "setting the same value posts nothing")
        #expect(defaults.bool(forKey: ChangeHighlightsSettings.scrollKey))
        #expect(!settings.scrollsOnChange, "highlights are off")
        settings.isEnabled = true
        #expect(settings.scrollsOnChange)
        settings.scrollsToChanges = false
        #expect(defaults.object(forKey: ChangeHighlightsSettings.scrollKey) == nil, "off removes the key")
        defaults.set("yes", forKey: ChangeHighlightsSettings.scrollKey)
        #expect(!settings.scrollsToChanges)
    }

    @Test("off, a live reload marks nothing")
    func offMarksNothing() async throws {
        defer { closeAll() }
        let (document, controller) = try await open(
            Self.shortSource, changeHighlightsSettings: highlightSettings(enabled: false))
        document.startLiveReload()
        try await save(Self.shortSource.replacingOccurrences(of: "Second", with: "Edited"), to: document)
        try await until("the page") { try await bodyText(controller).contains("Edited") }
        #expect(document.contentChanges == nil)
        #expect(try await barKinds(in: controller).isEmpty)
    }

    @Test("an edited block gets a bar beside it, a removed one a rule")
    func marksEditsAndDeletions() async throws {
        defer { closeAll() }
        let (document, controller) = try await open(Self.shortSource, changeHighlightsSettings: highlightSettings())
        document.showWindows()
        document.startLiveReload()

        try await save(
            Self.shortSource.replacingOccurrences(of: "Second paragraph.", with: "Second, edited."), to: document)
        #expect(document.contentChanges == SourceChanges(changedLines: [5...5]))
        try await until("the bar") { try await barKinds(in: controller) == ["changed"] }
        #expect(try await firstBarIsBeside("Second, edited.", in: controller))

        try await save("# Title\n\nFirst paragraph.\n\nThird paragraph.\n", to: document)
        try await until("the rule") { try await barKinds(in: controller) == ["before"] }
    }

    @Test("a change out of view is counted in the status bar, and the item scrolls to it")
    func offScreenChanges() async throws {
        defer { closeAll() }
        let (document, controller) = try await open(Self.longSource, changeHighlightsSettings: highlightSettings())
        document.showWindows()
        document.startLiveReload()

        try await save(
            Self.longSource.replacingOccurrences(of: "Paragraph 190.", with: "Paragraph 190, edited."), to: document)
        try await until("the count") { controller.statusBar.offScreenChanges == OffScreenChanges(above: 0, below: 1) }

        #expect(try await scrollY(controller) == 0, "without the scroll setting the view stays put")

        controller.scrollToNextChange(nil)
        try await until("the change is in view") { controller.statusBar.offScreenChanges == nil }
        #expect(try await scrollY(controller) > 0)
    }

    @Test("with scrolling on, a reload scrolls to the first change out of view")
    func scrollsToFirstChange() async throws {
        defer { closeAll() }
        let (document, controller) = try await open(
            Self.longSource, changeHighlightsSettings: highlightSettings(scrolls: true))
        document.showWindows()
        document.startLiveReload()

        let edited = Self.longSource
            .replacingOccurrences(of: "Paragraph 190.", with: "Paragraph 190, edited.")
            .replacingOccurrences(of: "Paragraph 120.", with: "Paragraph 120, edited.")
        try await save(edited, to: document)
        try await until("the first change is in view") {
            try await isInView("Paragraph 120, edited.", in: controller)
        }
        #expect(try await !isInView("Paragraph 190, edited.", in: controller))
    }

    @Test("with scrolling on, a reload with a change already in view doesn't scroll")
    func staysWithChangeInView() async throws {
        defer { closeAll() }
        let (document, controller) = try await open(
            Self.longSource, changeHighlightsSettings: highlightSettings(scrolls: true))
        document.showWindows()
        document.startLiveReload()

        let edited = Self.longSource
            .replacingOccurrences(of: "Paragraph 190.", with: "Paragraph 190, edited.")
            .replacingOccurrences(of: "Paragraph 2.", with: "Paragraph 2, edited.")
        try await save(edited, to: document)
        try await until("the count") { controller.statusBar.offScreenChanges == OffScreenChanges(above: 0, below: 1) }
        #expect(try await scrollY(controller) == 0)
    }

    @Test("a mark fades once it has been on screen")
    func fades() async throws {
        defer { closeAll() }
        let (document, controller) = try await open(Self.shortSource, changeHighlightsSettings: highlightSettings())
        document.showWindows()
        document.startLiveReload()
        try await save(Self.shortSource.replacingOccurrences(of: "Third", with: "Last"), to: document)
        try await until("the bar") { try await !barKinds(in: controller).isEmpty }
        try await until("the bar fades", timeout: .seconds(15)) { try await barKinds(in: controller).isEmpty }
    }

    @Test("turning the setting off, or another content change, clears the marks")
    func clears() async throws {
        defer { closeAll() }
        let settings = highlightSettings()
        let (document, controller) = try await open(Self.longSource, changeHighlightsSettings: settings)
        document.showWindows()
        document.startLiveReload()

        let first = Self.longSource.replacingOccurrences(of: "Paragraph 150.", with: "Changed.")
        try await save(first, to: document)
        try await until("the bar") { try await barKinds(in: controller) == ["changed"] }
        settings.isEnabled = false
        try await until("cleared") { try await barKinds(in: controller).isEmpty }
        #expect(controller.statusBar.offScreenChanges == nil)

        settings.isEnabled = true
        try await save(first.replacingOccurrences(of: "Paragraph 160.", with: "Changed."), to: document)
        try await until("the bar again") { try await barKinds(in: controller) == ["changed"] }
        let content = try #require(document.content)
        document.setContent(content)
        try await until("cleared by a re-render") { try await barKinds(in: controller).isEmpty }
        #expect(document.contentChanges == nil)
    }

    @Test("the counts message accepts only two small non-negative integers")
    func countsMessage() {
        #expect(
            ChangeMarksMessageHandler.offScreenChanges(from: ["above": 1, "below": 2])
                == OffScreenChanges(above: 1, below: 2))
        let invalid: [Any] = [
            ["above": -1, "below": 0], ["above": 1.5, "below": 0], ["above": "1", "below": 0], ["above": 1],
            ["above": 0, "below": 10_000_000], "1,2", [1, 2],
        ]
        for body in invalid {
            #expect(ChangeMarksMessageHandler.offScreenChanges(from: body) == nil, "\(body)")
        }
    }

    func bodyText(_ controller: DocumentWindowController) async throws -> String {
        try await evaluate("return document.body.innerText;", in: controller) as? String ?? ""
    }
}
