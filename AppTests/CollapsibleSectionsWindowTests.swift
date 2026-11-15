import AppKit
import PeepCore
import Testing
import WebKit

@testable import PeepApp

/// Collapsible sections' setting (`CollapsibleSectionsSettings`): persistence, every open window
/// following it live, and View > Collapse All Sections / Expand All Sections.
@MainActor
@Suite("Collapsible sections (windows)", .serialized, .timeLimit(.minutes(1)))
final class CollapsibleSectionsWindowTests: DocumentWindowTestCase {
    static let sectionsSource = "# One\n\none text\n\n# Two\n\ntwo text"

    func sectionsSettings() -> CollapsibleSectionsSettings {
        CollapsibleSectionsSettings(defaults: defaults, isPersistent: true)
    }

    func isEnabled(in controller: DocumentWindowController) async throws -> Bool {
        let result = try await controller.coordinator.webView.callAsyncJavaScript(
            "return document.documentElement.hasAttribute('data-peep-sections');", arguments: [:], in: nil,
            contentWorld: AppScripts.world)
        return (result as? NSNumber)?.boolValue == true
    }

    func shownCount(in controller: DocumentWindowController) async throws -> Int {
        let result = try await controller.coordinator.webView.callAsyncJavaScript(
            """
            return [...document.querySelector("article.markdown-body").children]
              .filter((element) => getComputedStyle(element).display !== "none").length;
            """, arguments: [:], in: nil, contentWorld: AppScripts.world)
        return (result as? NSNumber)?.intValue ?? -1
    }

    @Test("the setting is off by default, persists, reads bad values as off, and posts changes")
    func settingsPersist() {
        let settings = sectionsSettings()
        #expect(!settings.isEnabled)
        var posts = 0
        let token = NotificationCenter.default.addObserver(
            forName: CollapsibleSectionsSettings.didChangeNotification, object: settings, queue: nil
        ) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        settings.isEnabled = true
        settings.isEnabled = true
        #expect(posts == 1, "setting the same value posts nothing")
        #expect(defaults.bool(forKey: CollapsibleSectionsSettings.key))
        #expect(sectionsSettings().isEnabled, "a new instance reads it")
        settings.isEnabled = false
        #expect(defaults.object(forKey: CollapsibleSectionsSettings.key) == nil, "off removes the key")
        defaults.set("yes", forKey: CollapsibleSectionsSettings.key)
        #expect(!settings.isEnabled)
    }

    @Test("UI-test settings stay in memory")
    func settingsInMemory() {
        let settings = CollapsibleSectionsSettings(defaults: defaults, isPersistent: false)
        settings.isEnabled = true
        #expect(settings.isEnabled)
        #expect(defaults.object(forKey: CollapsibleSectionsSettings.key) == nil)
    }

    @Test("open windows follow the setting live, and new windows start with it")
    func windowsFollow() async throws {
        defer { closeAll() }
        let settings = sectionsSettings()
        let (_, first) = try await open(Self.sectionsSource, collapsibleSectionsSettings: settings)
        #expect(try await !isEnabled(in: first))

        settings.isEnabled = true
        try await until("the page turns it on") { try await isEnabled(in: first) }
        let (_, second) = try await open(name: "other.md", collapsibleSectionsSettings: settings)
        try await until("a new window starts with it") { try await isEnabled(in: second) }

        first.collapseAllSections(nil)
        try await until("collapse all") { try await shownCount(in: first) == 2 }
        first.expandAllSections(nil)
        try await until("expand all") { try await shownCount(in: first) == 4 }

        first.collapseAllSections(nil)
        try await until("collapse all again") { try await shownCount(in: first) == 2 }
        settings.isEnabled = false
        try await until("the page turns it off") { try await !isEnabled(in: first) }
        #expect(try await shownCount(in: first) == 4, "turning it off unfolds everything")
    }

    @Test("View > Collapse All Sections and Expand All Sections are enabled only while it is on")
    func menuValidation() async throws {
        defer { closeAll() }
        let settings = sectionsSettings()
        let (_, controller) = try await open(collapsibleSectionsSettings: settings)
        let collapse = try #require(item("Collapse All Sections", in: "View"))
        let expand = try #require(item("Expand All Sections", in: "View"))
        #expect(!controller.validateMenuItem(collapse))
        #expect(!controller.validateMenuItem(expand))
        settings.isEnabled = true
        #expect(controller.validateMenuItem(collapse))
        #expect(controller.validateMenuItem(expand))
    }
}
