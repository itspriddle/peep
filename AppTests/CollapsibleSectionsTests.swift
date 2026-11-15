import AppKit
import PeepCore
import Testing
import WebKit

@testable import PeepApp

/// Collapsible sections on the page (`App/Scripts/CollapsibleSections.js`) in a hosted
/// `WKWebView`: what a heading folds, nested state, live reload, unfolding on navigation and
/// find, and turning the feature off.
@MainActor
@Suite("Collapsible sections", .serialized, .timeLimit(.minutes(1)))
struct CollapsibleSectionsTests {
    let coordinator = WebViewCoordinator()
    /// Offscreen, never shown: gives the page an 800x600 viewport.
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered,
        defer: false)

    static let source = """
        # hi

        hi text

        ## there

        there text

        ## blah

        blah text

        ### another

        another text
        """

    /// Every top-level block's text, in order.
    static let allBlocks = ["hi", "hi text", "there", "there text", "blah", "blah text", "another", "another text"]

    init() {
        window.isReleasedWhenClosed = false
        window.contentView = coordinator.webView
        coordinator.find.pasteboard = FakeFindPasteboard()
        coordinator.collapsibleSections = true
    }

    static func page(_ source: String) -> RenderedPage {
        DocumentContent(source: source, fallbackTitle: "test.md").page
    }

    func load(_ source: String = source) async throws {
        try await coordinator.load(Self.page(source), baseURL: nil)
    }

    @discardableResult
    func evaluate(_ body: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
        try await coordinator.webView.callAsyncJavaScript(
            body, arguments: arguments, in: nil, contentWorld: AppScripts.world)
    }

    /// The text of each top-level block that is displayed.
    func shownBlocks() async throws -> [String] {
        let texts = try await evaluate(
            """
            return [...document.querySelector("article.markdown-body").children]
              .filter((element) => getComputedStyle(element).display !== "none")
              .map((element) => element.textContent.trim());
            """)
        return try #require(texts as? [String])
    }

    /// Clicks the top-level heading whose text is `text`, as a pointer does (`detail` 1, or 2 for
    /// the second click of a double-click).
    func click(_ text: String, detail: Int = 1) async throws {
        let clicked = try await evaluate(
            """
            const heading = [...document.querySelector("article.markdown-body").children]
              .find((element) => /^H[1-6]$/.test(element.tagName) && element.textContent.trim() === text);
            if (heading === undefined) {
              return false;
            }
            heading.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, detail, button: 0 }));
            return true;
            """, ["text": text, "detail": detail])
        #expect((clicked as? NSNumber)?.boolValue == true, "no heading \(text)")
    }

    // MARK: Folding

    @Test("a heading folds up to the next heading of the same or a higher level")
    func foldsSections() async throws {
        try await load()
        #expect(try await shownBlocks() == Self.allBlocks)

        try await click("there")
        #expect(try await shownBlocks() == ["hi", "hi text", "there", "blah", "blah text", "another", "another text"])
        try await click("there")

        try await click("blah")
        #expect(try await shownBlocks() == ["hi", "hi text", "there", "there text", "blah"])
        try await click("blah")

        try await click("hi")
        #expect(try await shownBlocks() == ["hi"])
        try await click("hi")
        #expect(try await shownBlocks() == Self.allBlocks)
    }

    @Test("a section folded inside a folded section stays folded when the outer one unfolds")
    func nestedState() async throws {
        try await load()
        try await click("another")
        try await click("hi")
        #expect(try await shownBlocks() == ["hi"])
        try await click("hi")
        #expect(try await shownBlocks() == ["hi", "hi text", "there", "there text", "blah", "blah text", "another"])
    }

    @Test("collapsed headings are marked, and only top-level headings fold")
    func markers() async throws {
        try await load("# Top\n\n> ## Quoted\n>\n> quoted text\n\nafter")
        try await click("Top")
        let state =
            try await evaluate(
                """
                const top = document.querySelector("article.markdown-body > h1");
                return [top.getAttribute("aria-expanded"), top.hasAttribute("data-peep-collapsed"),
                  document.documentElement.hasAttribute("data-peep-sections"),
                  getComputedStyle(top, "::after").content];
                """) as? [Any]
        #expect(state?[0] as? String == "false")
        #expect((state?[1] as? NSNumber)?.boolValue == true)
        #expect((state?[2] as? NSNumber)?.boolValue == true)
        #expect(state?[3] as? String != "none", "the chevron shows")
        #expect(try await shownBlocks() == ["Top"])
        try await click("Top")
        // The quoted heading isn't a direct child of the article: clicking it does nothing.
        let quotedClick = try await evaluate(
            """
            const quoted = document.querySelector("blockquote h2");
            quoted.dispatchEvent(new MouseEvent("click", { bubbles: true, detail: 1, button: 0 }));
            return quoted.hasAttribute("data-peep-collapsed");
            """)
        #expect((quotedClick as? NSNumber)?.boolValue == false)
        #expect(try await shownBlocks().count == 3)
    }

    @Test("the footnotes section never folds")
    func footnotesStay() async throws {
        try await load("# Title\n\nText with a note.[^1]\n\n[^1]: The note.")
        try await click("Title")
        let shown = try await shownBlocks()
        #expect(shown.first == "Title")
        #expect(shown.count == 2, "the heading and the footnotes: \(shown)")
        #expect(shown.last?.contains("The note.") == true)
    }

    @Test("a link in a heading navigates instead of folding, and a double-click nets no change")
    func clickRules() async throws {
        try await load("# Title [docs](https://example.com)\n\ntext")
        let linkClick = try await evaluate(
            """
            const link = document.querySelector("article.markdown-body > h1 a[href^='https:']");
            link.addEventListener("click", (event) => event.preventDefault(), { once: true });
            link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, detail: 1, button: 0 }));
            return document.querySelector("article.markdown-body > h1").hasAttribute("data-peep-collapsed");
            """)
        #expect((linkClick as? NSNumber)?.boolValue == false)

        try await click("Title docs", detail: 1)
        try await click("Title docs", detail: 2)
        #expect(try await shownBlocks().count == 2, "the second click of a double-click undoes the first")
    }

    @Test("Enter on a focused heading toggles it")
    func keyboard() async throws {
        try await load()
        try await evaluate(
            """
            const heading = document.querySelector("article.markdown-body > h2");
            heading.focus();
            heading.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }));
            """)
        #expect(try await shownBlocks() == ["hi", "hi text", "there", "blah", "blah text", "another", "another text"])
    }

    @Test("collapse all folds every section; expand all unfolds them")
    func collapseAndExpandAll() async throws {
        try await load()
        try await coordinator.collapseAllSections()
        #expect(try await shownBlocks() == ["hi"])
        try await click("hi")
        #expect(try await shownBlocks() == ["hi", "hi text", "there", "blah"], "the subsections stay collapsed")
        try await coordinator.expandAllSections()
        #expect(try await shownBlocks() == Self.allBlocks)
    }

    // MARK: Off

    @Test("off by default on a page: clicking does nothing and nothing is marked")
    func offByDefault() async throws {
        coordinator.collapsibleSections = false
        try await load()
        try await click("hi")
        #expect(try await shownBlocks() == Self.allBlocks)
        let marked = try await evaluate(
            "return document.querySelectorAll('[tabindex], [aria-expanded], [data-peep-collapsed]').length;")
        #expect((marked as? NSNumber)?.intValue == 0)
        try await coordinator.collapseAllSections()
        #expect(try await shownBlocks() == Self.allBlocks)
    }

    @Test("turning it off unfolds everything and removes the markers; on again starts unfolded")
    func turningOff() async throws {
        try await load()
        try await click("blah")
        coordinator.collapsibleSections = false
        try await coordinator.applyCollapsibleSectionsToPage()
        #expect(try await shownBlocks() == Self.allBlocks)
        let marked = try await evaluate(
            """
            return document.documentElement.hasAttribute("data-peep-sections")
              || document.querySelectorAll("[tabindex], [aria-expanded], [data-peep-collapsed], [data-peep-folded]")
                .length > 0;
            """)
        #expect((marked as? NSNumber)?.boolValue == false)
        coordinator.collapsibleSections = true
        try await coordinator.applyCollapsibleSectionsToPage()
        #expect(try await shownBlocks() == Self.allBlocks)
        try await click("there")
        #expect(try await shownBlocks().count == 7)
    }

    @Test("a heading's own tabindex from raw HTML survives turning it off")
    func keepsOwnTabIndex() async throws {
        try await load("<h2 tabindex=\"-1\">Raw</h2>\n\ntext")
        coordinator.collapsibleSections = false
        try await coordinator.applyCollapsibleSectionsToPage()
        let tabIndex = try await evaluate("return document.querySelector('h2').getAttribute('tabindex');")
        #expect(tabIndex as? String == "-1")
    }

    // MARK: Content swaps

    @Test("live reload keeps collapsed sections collapsed, matched by heading")
    func keepsStateOnReload() async throws {
        try await load()
        try await click("there")
        let edited = Self.source.replacingOccurrences(of: "blah text", with: "blah text, edited")
        try await coordinator.updateContent(with: Self.page("Intro line.\n\n" + edited), baseURL: nil)
        #expect(
            try await shownBlocks() == [
                "Intro line.", "hi", "hi text", "there", "blah", "blah text, edited", "another", "another text",
            ])
        try await coordinator.updateContent(
            with: Self.page(Self.source.replacingOccurrences(of: "## there", with: "## renamed")), baseURL: nil)
        #expect(
            try await shownBlocks() == Self.allBlocks.map { $0 == "there" ? "renamed" : $0 },
            "a renamed heading unfolds")
    }

    // MARK: Unfolding on navigation

    @Test("scrolling to a source line or a fragment inside a folded section unfolds it")
    func navigationUnfolds() async throws {
        try await load()
        try await coordinator.collapseAllSections()
        // "another text" is line 15.
        try await coordinator.scroll(toSourceLine: 15)
        #expect(try await shownBlocks() == ["hi", "hi text", "there", "blah", "blah text", "another", "another text"])

        try await coordinator.collapseAllSections()
        let found = try await coordinator.scroll(toFragment: "another")
        #expect(found)
        #expect(
            try await shownBlocks() == ["hi", "hi text", "there", "blah", "blah text", "another"], "the heading shows")
    }

    @Test("reading position ignores folded blocks")
    func readingPositionSkipsFolded() async throws {
        let long = (1...80).map { "Paragraph \($0)." }.joined(separator: "\n\n")
        try await load("# One\n\n\(long)\n\n# Two\n\n\(long)")
        try await click("One")
        try await coordinator.scroll(toSourceLine: 1)
        let line = try await coordinator.currentSourceLine()
        #expect(line < 2, "the top is line 1, not a folded block: \(line)")
    }

    @Test("find counts matches in folded sections and unfolds the one it selects")
    func findUnfolds() async throws {
        try await load()
        try await coordinator.collapseAllSections()
        let find = coordinator.find
        find.show()
        find.setQuery("another text")
        await find.waitUntilIdle()
        #expect(find.matchCount == 1)
        find.next()
        await find.waitUntilIdle()
        try await Task.sleep(for: .milliseconds(50))
        #expect(try await shownBlocks().contains("another text"))
    }
}
