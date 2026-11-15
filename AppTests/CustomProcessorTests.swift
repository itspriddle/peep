import AppKit
import Foundation
import PeepCore
import Testing

@testable import PeepApp

/// The custom processor in the app (#106): documents render with it on open and live reload,
/// its HTML sanitized; a failure falls back to Peep's renderer with the reason for the bar;
/// changing it re-renders open documents; documents can't turn it on. It shares the
/// preprocessor's store and model (`CustomProgramSettings`, `CustomProgramModel`), whose own
/// suites cover the rest. Scripts are written per test (`PreprocessorScripts`).
@MainActor
@Suite("Custom processor", .serialized, .timeLimit(.minutes(2)))
final class CustomProcessorTests: DocumentWindowTestCase {
    var scripts: PreprocessorScripts { PreprocessorScripts(folder: folder) }

    func store(running executable: String, arguments: [String] = []) -> CustomProgramSettings {
        PreprocessorScripts.settings(.processor, running: executable, arguments: arguments, defaults: defaults)
    }

    func bodyHTML(_ controller: DocumentWindowController) async throws -> String {
        try await controller.coordinator.webView.callAsyncJavaScript(
            "return document.querySelector('.markdown-body').innerHTML;", arguments: [:], in: nil,
            contentWorld: AppScripts.world) as? String ?? ""
    }

    @Test("an open document renders the processor's sanitized HTML, with its headings; Copy as HTML copies it")
    func runsOnOpen() async throws {
        defer { closeAll() }
        let store = store(running: try scripts.htmlProcessor())
        let source = "---\ntitle: Front\n---\n# Markdown <b>\n"
        let (document, controller) = try await open(source, customProcessorSettings: store)
        try await until("the processed page") { try await bodyHTML(controller).contains("class=\"body\"") }
        let content = try #require(document.content)
        #expect(content.processorError == nil)
        #expect(content.processedHTML?.contains("<script>") == true, "kept as the processor wrote it")
        #expect(content.page.title == "Front")
        #expect(content.page.headings.map(\.slug) == ["processed", "second-part"])
        #expect(content.page.body.contains("# Markdown &lt;b&gt;\n</pre>"), "the body after the frontmatter")
        #expect(!content.page.body.contains("<script"))
        #expect(!content.page.body.contains("title: Front"))
        #expect(store.lastRun?.documentName == "notes.md")
        #expect(store.lastRun?.error == nil)

        await controller.writeHTML(to: pasteboard)
        let copied = try #require(pasteboard.string(forType: .html))
        #expect(copied.contains("<h1 id=\"processed\">"))
        #expect(!copied.contains("<script"))
    }

    @Test("it runs after the preprocessor")
    func afterPreprocessor() async throws {
        defer { closeAll() }
        let preprocessor = PreprocessorScripts.settings(running: try scripts.upcase(), defaults: defaults)
        let processor = store(running: try scripts.htmlProcessor())
        let (document, _) = try await open(
            "# quiet\n", customPreprocessorSettings: preprocessor, customProcessorSettings: processor)
        #expect(document.content?.page.body.contains("<pre class=\"body\"># QUIET\n</pre>") == true)
    }

    @Test("a failing processor falls back to Peep's renderer and reports why")
    func failureFallsBack() async throws {
        defer { closeAll() }
        let store = store(running: try scripts.fail(stderr: "pandoc: bad option"))
        let (document, _) = try await open("# Plain\n\nPeep renders this.\n", customProcessorSettings: store)
        let content = try #require(document.content)
        let error = try #require(content.processorError)
        #expect(error.kind == .processor)
        #expect(error.reason == .exited(status: 3))
        #expect(error.standardError.contains("pandoc: bad option"))
        #expect(content.processedHTML == nil)
        #expect(content.preprocessorError == nil)
        #expect(content.page.body.contains("Peep renders this."))
        #expect(content.page.headings.first?.sourceLine == 1, "Peep's own render")
        #expect(store.lastRun?.error == error)
    }

    @Test("a live reload runs it again, and turning it off re-renders with Peep in place")
    func liveReloadAndSettings() async throws {
        defer { closeAll() }
        let store = store(running: try scripts.htmlProcessor())
        let (document, controller) = try await open("first version\n", customProcessorSettings: store)
        document.startLiveReload()
        try await until("the first render") { try await bodyHTML(controller).contains("first version\n</pre>") }
        try Data("second version\n".utf8).write(to: try #require(document.fileURL))
        try await until("the reload") { try await bodyHTML(controller).contains("second version\n</pre>") }

        store.isEnabled = false
        try await until("Peep's render") { try await bodyHTML(controller).contains("<p data-source-line") }
        #expect(document.content?.preferences.customProcessor == nil)
        #expect(document.content?.processedHTML == nil)
    }

    @Test("closing a document stops its processor's process group")
    func closeStopsScript() async throws {
        let store = store(running: try scripts.hang())
        let file = folder.appending(path: "close.md")
        try Data("# Closing\n".utf8).write(to: file)
        let document = try MarkdownDocument(contentsOf: file, ofType: Self.markdownType)
        document.customProcessorSettings = store
        try await until("the script starts") { !scripts.pids().isEmpty }
        document.close()
        #expect(try await scripts.processesGone())
        #expect(document.content == nil, "the cancelled run shows nothing")
    }

    @Test("frontmatter can't turn it on or choose a program")
    func frontmatterCantEnable() async throws {
        defer { closeAll() }
        let marker = folder.appending(path: "ran")
        let script = try scripts.write("marker.sh", "touch '\(marker.path(percentEncoded: false))'\ncat")
        let source = """
            ---
            peep:
              processor: \(script)
              customProcessor: \(script)
            CustomProcessorEnabled: true
            CustomProcessorExecutable: \(script)
            ---
            # Untrusted
            """
        let (document, _) = try await open(source)
        #expect(document.content?.preferences.customProcessor == nil)
        #expect(document.content?.processedHTML == nil)
        #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
        #expect(!CustomProgramSettings.processor.isEnabled)
    }

    @Test("the processor's store is separate from the preprocessor's, with its own keys")
    func separateStore() {
        let processor = CustomProgramSettings(kind: .processor, defaults: defaults, isPersistent: true)
        let preprocessor = CustomProgramSettings(kind: .preprocessor, defaults: defaults, isPersistent: true)
        processor.executablePath = "/bin/cat"
        processor.isEnabled = true
        #expect(processor.preference?.executablePath == "/bin/cat")
        #expect(preprocessor.preference == nil)
        #expect(defaults.string(forKey: "CustomProcessorExecutable") == "/bin/cat")
        #expect(defaults.bool(forKey: "CustomProcessorEnabled"))
        #expect(defaults.object(forKey: "CustomPreprocessorExecutable") == nil)
    }

    @Test("Settings' processor section turns it on only through the warning")
    func settingsWarning() async {
        let store = CustomProgramSettings(kind: .processor, defaults: defaults, isPersistent: false)
        let choice = URL(filePath: "/bin/cat")
        let model = CustomProgramModel(settings: store) { choice }
        #expect(model.kind == .processor)
        await model.chooseExecutable()
        model.setEnabled(true)
        #expect(model.isConfirmingEnable)
        #expect(!store.isEnabled)
        model.confirmEnable()
        #expect(store.isEnabled)
        #expect(model.kind.enableWarning(programName: "“cat”").contains("to render every document"))
    }
}
