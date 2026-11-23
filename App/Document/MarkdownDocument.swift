import AppKit
import PeepCore
import os

/// One open Markdown file. Peep is a viewer: the document reads and re-reads its file but never
/// writes it.
///
/// `NSDocument` gives us opening, revert, recents, window tabs, and state restoration. Live
/// reload is `LiveReloader` (a kqueue watcher), not NSDocument's file presenter, which is late
/// and misses deletes (#21). The document owns the source text and the rendered page
/// (`content`); each window's `DocumentWindowController` displays it.
///
/// Opening reads and decodes the file on the main thread (so a missing or non-UTF-8 file fails
/// the open with NSDocument's own error) and renders it off the main actor (#32): the window
/// appears right away, painted with the theme background, and the page loads when the render
/// finishes.
///
/// Settings > Markdown (#55) applies to open documents: the document follows
/// `MarkdownSettings.didChangeNotification` and renders its source again with the new
/// preferences, and each window swaps the result in place like a live reload (keeping the
/// reading position).
///
/// The custom preprocessor (#57), when the reader turned it on, is part of every render: the
/// first render waits for it, each live reload runs it again, and a newer render, a newer
/// `setContent(_:)`, or closing the document cancels the run in flight, which stops the
/// script's process group. Changing it in Settings renders open documents again.
/// Standard input (`cmd | peep`, #68) is a document with no file (`init(standardInput:)`), the
/// only untitled document a viewer has: titled from its first heading or "Standard Input", no
/// live reload, and its window isn't restored. Settings changes render it again as any other.
///
/// Registered as `NSDocumentClass` for the document types declared in project.yml.
@Observable
final class MarkdownDocument: NSDocument {
    /// The name of a standard input document (`init(standardInput:)`) with no title of its own.
    nonisolated static let standardInputName = "Standard Input"

    /// The source and rendered page from the last successful read; `nil` until the first
    /// render finishes.
    private(set) var content: DocumentContent?

    /// The render in flight (of a read, or after a Settings change) while it runs off the main
    /// actor, for tests to await. Cancelling it stops a custom preprocessor it is running.
    @ObservationIgnored private(set) var pendingRender: Task<Void, Never>?
    /// What `pendingRender` renders, so a Settings change can restart it.
    @ObservationIgnored private var pendingRenderInput: RenderInput?
    /// Bumped by every read, every `setContent(_:)`, and `close()`: a render that finishes
    /// under an older value was overtaken (by a newer read, a live reload, or the window
    /// closing) and is dropped.
    @ObservationIgnored private var contentGeneration = 0

    /// Whether the window shows the file's current contents; set by live reload.
    var fileStatus: FileStatus = .current

    /// Whether a render (`pendingRender`) or a live reload is in flight: the windows show a
    /// progress indicator if it runs long (#58). Each window hears of a change through
    /// `DocumentWindowController.renderActivityDidChange()`.
    private(set) var isRendering = false

    /// Watches the file while the document has windows (live reload).
    @ObservationIgnored private var liveReloader: LiveReloader?

    /// What the last live reload changed, for the windows to mark ("Highlight changes when a file
    /// is saved"); `nil` after any other `setContent(_:changes:)` (a first load, revert, or
    /// Settings re-render) and while the setting is off.
    @ObservationIgnored private(set) var contentChanges: SourceChanges?

    /// The setting that decides whether live reloads work out `contentChanges`. Tests set their
    /// own store right after opening.
    @ObservationIgnored var changeHighlightsSettings: ChangeHighlightsSettings = .shared

    /// The window the last live reload brings to the front ("Bring the window to the front when
    /// a file is saved"): set only when that reload changed the text while the setting is on,
    /// `nil` after any other `setContent(_:changes:textChanged:)`.
    @ObservationIgnored private(set) weak var raiseTarget: DocumentWindowController?

    /// The setting that decides whether a live reload sets `raiseTarget`. Tests set their own
    /// store right after opening.
    @ObservationIgnored var raiseOnChangeSettings: RaiseOnChangeSettings = .shared

    /// The Markdown settings (#55) this document renders with. Changing them (or the store)
    /// renders the document again. Tests set their own store right after opening.
    @ObservationIgnored var markdownSettings: MarkdownSettings = .shared {
        didSet {
            renderIfSettingsChanged()
        }
    }

    /// The custom preprocessor settings (#57) this document renders with. Changing them (or
    /// the store) renders the document again. Tests set their own store right after opening.
    @ObservationIgnored var customPreprocessorSettings: CustomProgramSettings = .preprocessor {
        didSet {
            renderIfSettingsChanged()
        }
    }

    /// The custom processor's settings (#106), followed like `customPreprocessorSettings`.
    @ObservationIgnored var customProcessorSettings: CustomProgramSettings = .processor {
        didSet {
            renderIfSettingsChanged()
        }
    }

    override init() {
        super.init()
        let center = NotificationCenter.default
        let selector = #selector(markdownSettingsDidChange(_:))
        center.addObserver(self, selector: selector, name: MarkdownSettings.didChangeNotification, object: nil)
        center.addObserver(
            self, selector: selector, name: CustomProgramSettings.didChangeNotification, object: nil)
    }

    /// A document of standard input's Markdown (#68): no file, rendered like a read.
    convenience init(standardInput source: String) {
        self.init()
        render(source, of: nil)
    }

    override static var autosavesInPlace: Bool { false }

    /// What NSDocument names a document with no file (standard input): "Standard Input",
    /// numbered after the first, rather than "Untitled".
    override func defaultDraftName() -> String {
        Self.standardInputName
    }

    /// Signposts for opening (`Read` on main, `Render` off main), in Instruments' Points of
    /// Interest. Release builds keep them; they cost nothing unless recorded.
    nonisolated static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "peep", category: .pointsOfInterest)

    override func makeWindowControllers() {
        LaunchTiming.mark("makeWindowControllers")
        // The first window of the launch gets the web view started at launch (#40).
        let controller = DocumentWindowController(coordinator: WebViewPrewarmer.shared.takeCoordinator())
        addWindowController(controller)
        // Standard input has no file to reopen: its window isn't restored.
        controller.window?.isRestorable = fileURL != nil
        startLiveReload()
    }

    override func showWindows() {
        super.showWindows()
        LaunchTiming.mark("windowShown")
    }

    override func close() {
        liveReloader?.stop()
        liveReloader = nil
        // A closed document no longer follows Settings > Markdown.
        NotificationCenter.default.removeObserver(self, name: MarkdownSettings.didChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(
            self, name: CustomProgramSettings.didChangeNotification, object: nil)
        dropPendingRender()
        updateRenderActivity()
        super.close()
    }

    // MARK: Reading

    /// Reads the file and starts rendering it off the main actor; `setContent(_:)` shows the
    /// result. NSDocument calls this for the initial open and for every revert
    /// (`revert(toContentsOf:ofType:)`).
    ///
    /// Reading and UTF-8 decoding stay here, on the main thread, so an unreadable or non-UTF-8
    /// file still fails the open (or revert) with the error NSDocument presents. They take a few
    /// milliseconds for 5 MB; rendering is what took hundreds (#27).
    override nonisolated func read(from url: URL, ofType typeName: String) throws {
        LaunchTiming.mark("read")
        let interval = Self.signposter.beginInterval("Read", id: Self.signposter.makeSignpostID())
        defer { Self.signposter.endInterval("Read", interval) }
        let source = try DocumentContent.source(from: Data(contentsOf: url))
        // NSDocument reads on the main thread unless `canConcurrentlyReadDocuments(ofType:)`
        // returns true, which this class does not (`NSDocument.init` is main-actor and traps
        // off main under Swift 6).
        MainActor.assumeIsolated {
            render(source, of: url)
        }
    }

    /// Renders `source` (the contents of `url`, or standard input's when nil) off the main
    /// actor, then shows it with
    /// `setContent(_:)` unless something newer replaced the content or the document closed
    /// first. Starting a render drops the one in flight.
    ///
    /// The first render of an open waits here (for the renderer, and for the custom
    /// preprocessor when one is on, up to its timeout); the window shows its blank,
    /// theme-colored page meanwhile (`DocumentWindowController`, `prepareForFirstLoad()`).
    func render(_ source: String, of url: URL?) {
        dropPendingRender()
        let generation = contentGeneration
        let preferences = renderPreferences
        pendingRenderInput = RenderInput(source: source, url: url, preferences: preferences)
        pendingRender = Task { [weak self] in
            guard let content = try? await Self.renderContent(source, of: url, preferences: preferences),
                let self, generation == self.contentGeneration
            else {
                return
            }
            self.setContent(content)
        }
        updateRenderActivity()
    }

    /// What a render of this document uses now: Settings > Markdown's preferences (#55) and the
    /// custom preprocessor (#57) and processor (#106), if on. Read on the main actor and passed
    /// to the render.
    var renderPreferences: MarkdownPreferences {
        var preferences = markdownSettings.preferences
        preferences.customPreprocessor = customPreprocessorSettings.preference
        preferences.customProcessor = customProcessorSettings.preference
        return preferences
    }

    /// Renders a document's content with `preferences` (`renderPreferences`, read on the main
    /// actor by the caller) on a detached task, so it runs off the main actor. Cancelling the
    /// calling task cancels the render, which stops a custom preprocessor run (#57) and throws
    /// `CancellationError`; a render without one finishes and is dropped by the caller.
    nonisolated static func renderContent(
        _ source: String, of url: URL?, preferences: MarkdownPreferences
    ) async throws -> DocumentContent {
        let work = Task.detached(priority: .userInitiated) {
            let interval = signposter.beginInterval(
                "Render", id: signposter.makeSignpostID(), "\(source.utf8.count) bytes")
            defer { signposter.endInterval("Render", interval) }
            if let delay = UITestHooks.renderDelay {
                try await Task.sleep(for: delay)
            }
            return try await DocumentContent.rendering(source, of: url, preferences: preferences)
        }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }

    /// Marks the render in flight, if any, as stale and cancels it. A custom preprocessor it
    /// is running is stopped; otherwise its work finishes in the background (the renderer
    /// can't be interrupted) and the result is dropped. Callers call `updateRenderActivity()`
    /// once they're done, so a render replaced by another never reports a gap.
    private func dropPendingRender() {
        contentGeneration += 1
        pendingRender?.cancel()
        pendingRender = nil
        pendingRenderInput = nil
    }

    /// Replaces the content and tells each window to show it. The single path every (re)load
    /// goes through. A render still in flight from an earlier read is older than `content`
    /// and is dropped (and cancelled, stopping its custom preprocessor run).
    ///
    /// Content rendered before Settings > Markdown changed (a first render or live reload that
    /// was already running) is shown, then rendered again with the current preferences.
    ///
    /// `changes` is what a live reload changed (`LiveReloader`); every other caller leaves it
    /// out, which clears the windows' marks. `textChanged` says a live reload read new text,
    /// which brings a window forward while `raiseOnChangeSettings` is on (`raiseTarget`).
    func setContent(_ content: DocumentContent, changes: SourceChanges? = nil, textChanged: Bool = false) {
        LaunchTiming.mark("rendered")
        dropPendingRender()
        self.content = content
        contentChanges = changes
        raiseTarget = textChanged && raiseOnChangeSettings.isEnabled ? frontmostWindowController() : nil
        let documentName: String = fileURL?.lastPathComponent ?? displayName
        if content.preferences.customPreprocessor != nil {
            customPreprocessorSettings.recordRun(
                CustomProgramRun(documentName: documentName, date: .now, error: content.preprocessorError))
        }
        if content.preferences.customProcessor != nil {
            customProcessorSettings.recordRun(
                CustomProgramRun(documentName: documentName, date: .now, error: content.processorError))
        }
        fileStatus = .current
        for case let controller as DocumentWindowController in windowControllers {
            controller.documentContentDidChange()
        }
        renderIfSettingsChanged()
        updateRenderActivity()
    }

    /// The document's window nearest the front (the one a reader last used), else its first
    /// window (all minimized or hidden).
    private func frontmostWindowController() -> DocumentWindowController? {
        let controllers = windowControllers.compactMap { $0 as? DocumentWindowController }
        for window in NSApp.orderedWindows {
            if let controller = controllers.first(where: { $0.window === window }) {
                return controller
            }
        }
        return controllers.first
    }

    /// Updates `isRendering` from the render and the live reload in flight, and tells the
    /// windows when it changed.
    func updateRenderActivity() {
        let rendering = pendingRender != nil || liveReloader?.isReloading == true
        guard rendering != isRendering else {
            return
        }
        isRendering = rendering
        for case let controller as DocumentWindowController in windowControllers {
            controller.renderActivityDidChange()
        }
    }

    // MARK: Markdown settings (#55)

    @objc private func markdownSettingsDidChange(_ notification: Notification) {
        let object = notification.object as AnyObject?
        guard object === markdownSettings || object === customPreprocessorSettings || object === customProcessorSettings
        else {
            return
        }
        renderIfSettingsChanged()
    }

    /// Renders the current source again if it was rendered with other preferences than
    /// `renderPreferences` are now (Settings > Markdown, the custom preprocessor). The windows
    /// swap the result in place (`setContent(_:)`).
    ///
    /// A render or live reload in flight is newer than `content`: one with the current
    /// preferences is left to finish, and one with outdated preferences starts again, so turning
    /// a slow preprocessor off doesn't wait for it.
    private func renderIfSettingsChanged() {
        let preferences = renderPreferences
        liveReloader?.restartIfOutdated(preferences: preferences)
        if let pending = pendingRenderInput {
            if pending.preferences != preferences {
                render(pending.source, of: pending.url)
            }
            return
        }
        guard let content, content.preferences != preferences else {
            return
        }
        render(content.source, of: fileURL)
    }

    // MARK: Live reload

    /// Starts reloading the document when its file changes. `makeWindowControllers()` calls
    /// this; `close()` stops it.
    func startLiveReload(timing: FileWatcher.Timing = FileWatcher.Timing()) {
        guard liveReloader == nil else {
            return
        }
        let reloader = LiveReloader(document: self, timing: timing)
        reloader.start()
        liveReloader = reloader
    }

    /// The reload in flight, if any (for tests).
    var pendingReload: Task<Void, Never>? { liveReloader?.pendingReload }

    // `LiveReloader`'s `FileWatcher` owns change detection and file location. NSFilePresenter
    // callbacks arrive about a second late for edits by other processes and stop after a
    // delete (measured in #21), so they only ask the watcher to check. They don't call super:
    // NSDocument would follow a move to wherever the file went, including Vim's backup name
    // or the Trash, and the watcher decides that instead.

    override nonisolated func presentedItemDidChange() {
        Task { @MainActor in
            self.liveReloader?.checkForChanges()
        }
    }

    override nonisolated func presentedItemDidMove(to newURL: URL) {
        Task { @MainActor in
            self.liveReloader?.checkForChanges()
        }
    }

    override nonisolated func accommodatePresentedItemDeletion(
        completionHandler: @escaping @Sendable ((any Error)?) -> Void
    ) {
        // Keep the window and its last render; the watcher reports the deletion.
        completionHandler(nil)
        Task { @MainActor in
            self.liveReloader?.checkForChanges()
        }
    }

    // MARK: Viewer only

    override nonisolated func data(ofType typeName: String) throws -> Data {
        throw CocoaError(.fileWriteNoPermission)
    }
}

/// What a render renders: a document's text, its file (nil for standard input), and the
/// preferences it is rendered with.
private struct RenderInput {
    let source: String
    let url: URL?
    let preferences: MarkdownPreferences
}
