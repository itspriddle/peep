# CLAUDE.md

Peep (site: peep.now) is a native macOS Markdown viewer with a CLI, `peep`.
Read `docs/VISION.md` (principles, architecture, security model) and `docs/ROADMAP.md` (milestones,
process) before planning work.

## Commands

```sh
make generate         # regenerate Peep.xcodeproj from project.yml (run after adding/removing files)
make test-core        # cli-docs, then swift test (PeepCore, CLI), no Xcode project needed
make cli-docs         # man page + zsh/bash/fish completions into build/cli-docs (generated, #71)
make test             # core + app unit tests (not UI tests)
make test-ui          # XCTest UI tests; always signed (team or ad hoc), drives the GUI
make record-theme-snapshots  # re-record bundled theme references for this macOS version (#39)
make build            # app + embedded CLI (signed via Config/Local.xcconfig); SIGN=0 for unsigned
make lint             # swiftlint --strict + swift format lint --strict + check-version (CI runs this)
scripts/bump-version X.Y.Z   # set MARKETING_VERSION and PeepInfo.version, increment CURRENT_PROJECT_VERSION
scripts/check-version [vX.Y.Z]  # fail if those versions disagree, or don't match the tag
scripts/render-cask X.Y.Z SHA256  # print the Homebrew cask (Packaging/homebrew/peep.rb) for a release
make release          # scripts/package-release: signed, notarized, stapled build/release/Peep-X.Y.Z.dmg
                      # (+ .sha256); NOTARIZE=0 (--skip-notarize) for a dry run; docs/RELEASING.md
scripts/release-appcast [--previous F] [--notes F] DMG  # signed appcast.xml next to the DMG
                      # (SPARKLE_ED_PRIVATE_KEY on stdin to Sparkle's tools; the release workflow)
make format           # auto-format; run before committing
make emoji            # regenerate Generated/EmojiTable.swift from github/gemoji (pinned commit)
make html-entities    # regenerate Generated/HTMLEntityTable.swift from the WHATWG entity list
make app-icon         # regenerate AppIcon.appiconset and Site/public icons from Branding/*.svg
make vendor-highlightjs  # re-vendor highlight.js (HLJS_VERSION=x.y.z) as generated Swift
make vendor-github-markdown-css  # re-vendor the GitHub theme (GHCSS_VERSION=x.y.z) as generated Swift
make vendor-mermaid   # re-vendor mermaid (MERMAID_VERSION=x.y.z) into Vendor/mermaid (needs npm)
swift run peep --html FILE   # render to stdout without Xcode
scripts/measure-cold-open [-f] [-c] FILE  # Release cold open to first paint, median of N launches
                                     # (GUI); -f adds the bare-WKWebView floor (scripts/cold-open-floor.swift),
                                     # -c times `open -n -a` against `peep FILE` from the command's start
```

`.NOTPARALLEL` is set because the user's shell exports `MAKEFLAGS=-j9`; concurrent xcodebuilds
lock the build database.

## Layout

- `Sources/PeepCore`: all rendering logic (parse, transform, HTML, themes, preprocessors). No UI
  imports. New logic goes here so it is testable with `swift test`.
  - `Parsing/`: `MarkdownParser` wraps swift-cmark's C API (the only code that imports
    `cmark_gfm`); `MarkdownExtension` lists GFM extensions, which flavors enable.
  - `Flavors/`: `Flavor` (id, name, extensions, transforms; syntax only) with `gfm` (default)
    and `commonmark`; `FlavorRegistry` resolves ids (unknown → GFM). A flavor is one
    `static let` plus a line in `FlavorRegistry.bundled` plus `Fixtures/flavors/<id>/`.
  - `AST/`: `MarkdownNode`, our `Sendable` syntax tree (CommonMark + GFM kinds, source ranges).
  - `Rendering/`: `HTMLRenderer` walks the AST to HTML; `MarkdownRenderer`, `RenderOptions`, and
    `RenderedDocument` are the public API. `HTMLRenderer+Pipeline.swift` is the render pipeline
    (VISION): custom preprocessor (`SourcePreprocessor`, before `render(_:)`) → frontmatter →
    flavor resolution → parse → transforms → HTML. `RenderOptions.flavor` picks syntax;
    viewer features are separate toggles. `RenderOptions.spec` turns every Peep addition off; a
    new toggle adds one line there. Heading slugs, footnote ids, and `data-source-line` live here.
  - `Sanitizing/`: `HTMLSanitizer` allowlist for raw-HTML nodes only (renderer output is trusted,
    so everything the renderer emits must be escaped by construction).
  - `Frontmatter/`: YAML/TOML detection, Yams parsing with size/alias caps.
  - `Overrides/`: `DocumentOverrides` (#54), the frontmatter's `peep:` mapping (`flavor`,
    `theme`, `wikilinks`), with ignored keys reported in `RenderedDocument.overrides`.
    `RenderOptions.applying(_:)` is the one place it changes a render (the flavor and the
    `.wikiLinks` built-in preprocessor only): never route a safety setting through it.
  - `Transforms/`: AST passes. `MarkdownTransform` (enum; declaration order is run order:
    alerts, wiki links, color swatches, emoji) names each pass; its implementation conforms to
    `MarkdownTreeTransform`. Enabled by `Flavor.transforms` or
    `RenderOptions.builtInPreprocessors`. Emoji shortcodes and GitHub alerts (`GitHubAlerts`,
    top-level `> [!NOTE]` quotes to `MarkdownNode.Kind.alert`; markup and Octicons in
    `Rendering/HTMLRenderer+Alerts.swift`) live here, and so do wiki links (`WikiLinks`, #53:
    `[[Page]]` text to `MarkdownNode.Kind.wikiLink`; markup in `HTMLRenderer+WikiLinks.swift`).
  - `ColorSwatches/`: `SwatchColor` (GitHub's color code forms, checked with `gh api markdown`:
    `#RRGGBB`, `rgb()`/`rgba()`, `hsl()`; kept as bytes, written only as `hex`) and the
    `ColorSwatches` transform (`MarkdownTransform.colorSwatches`, an opt-in built-in
    preprocessor; the one pass that reads `code`: a whole-literal color becomes
    `MarkdownNode.Kind.colorCode`, rendered as the code plus `span.peep-color-swatch`).
  - `WikiLinks/`: wiki link pages and resolution (#53). `WikiPage` (the naming rule),
    `WikiLinkResolver` (injected into `HTMLRenderer.wikiLinkResolver`; the search rules never
    read the disk), `FolderWikiLinkResolver` (document folder, then allowed root, entry cap, over
    an injected `WikiLinkFolderReader`), `FileSystemFolderReader` (the real reader for the app
    and CLI: regular files and folders only, no symbolic links or packages), and `SourceLines`
    (which bracket bytes were written as is rather than escaped).
  - `Preprocessor/`: the custom program runner (#56; VISION's security model has the
    contract and limits), shared by `CustomPreprocessor` and `CustomProcessor` (#106, its HTML
    replaces stages 4-6: `HTMLRenderer.prepare(_:)` then `render(processedHTML:of:)`, which
    sanitizes with `HTMLSanitizerMode.processorOutput`; `SourceProcessor`) through
    `CustomProgramRunner`, with a `CustomProgramKind` naming the program in
    `PreprocessorError.message`. `CustomPreprocessor.run(input:documentURL:)` is async and
    cancellable. `PreprocessorConfiguration` validates the executable and
    `PreprocessorLimits` holds the bounds; failures are `PreprocessorError`.
    `PreprocessorEnvironment` builds the env and working directory, `PreprocessorProcess`
    calls `posix_spawn`, and `PreprocessorSession` is the kqueue I/O loop on a dedicated
    thread. `for(documentURL:)` is the pipeline's `SourcePreprocessor`. Every descriptor goes
    through `PreprocessorDescriptors`, which the leak tests count. Fixture scripts are in
    `Tests/PeepCoreTests/Fixtures/preprocessors`.
  - `Themes/`: `Theme` (CSS plus `ThemeBackground`), `ThemeRegistry` (the one place the app and
    CLI get a theme; unknown ids fall back to GitHub), `ThemeBase` (the base layer every page
    gets; `!important` there means protected from themes), and `ThemeLayer` (cascade layers
    `peep-base` → `peep-theme` → `peep-user`, one `<style id>` each). Bundled themes are
    `extension Theme { static let … }` files here.
    `Themes/Custom/`: custom theme files (#35): `CustomTheme` (header, id), `CustomThemeCSS` (the
    safety check; `CustomThemeCSSScanner` tokenizes), `CustomThemeFolder` (reading the folder).
  - `LocalResources/`: the app's `peep-doc://<token>/<path>` URLs (`DocumentURLScheme`), the
    allowed-root rule, `LocalImagePolicy`, which approves every local image read, and
    `RootRelativeURL` (`/docs/x.png` resolved against the allowed root, `RenderOptions.linkRoot`).
  - `RemoteImages/`: `RemoteImage` (what counts as remote), `RemoteImagePolicy`
    (`RenderOptions.remoteImages`), and the blocked-image placeholder markup.
  - `Navigation/`: `LinkPolicy`, the viewer's one navigation policy (link URL to `LinkAction`),
    and `CopyableLink` (what Copy Link copies; never a `peep-doc:` URL).
  - `Outline/`: `DocumentOutline` (heading tree) and `OutlineTracker` (current section).
  - `Statistics/`: `WordCount` (the words a reader sees: the transformed body, without
    frontmatter, URLs, image alt, raw HTML, or emoji; ICU word segmentation), computed in the
    pipeline as `RenderedDocument.wordCount`.
  - `Changes/`: `SourceChanges` (which lines of a live reload's new text changed: line diff of
    the rendered sources after trimming common lines, blank lines never reported, a middle past
    `lineDiffLimit` reported as one range).
  - `Highlighting/`: highlight.js in JavaScriptCore; `HighlightValidator` re-serializes its output.
  - `Diagrams/` (M7, `RenderOptions.diagrams`): fenced blocks drawn as static SVG in pure Swift.
    `DiagramRendering` is the AST pass (run by `HTMLRenderer.drawingDiagrams(in:)` before
    highlighting and the word count; 1 MB per block, 200k coordinates per document) setting the
    internal `CodeBlock.diagramSVG`; `HTMLRenderer+Diagrams` writes the `figure.peep-diagram`.
    `DiagramKind` names the languages (first info-string word, case-insensitive): a new kind is
    a case plus its `render(_:budget:)` branch. `SVGWriter` is the only markup source (fixed
    names, escaped text, `SVGNumber`s, `SVGPath`); never write an input string. Maps:
    `GeoJSON` / `TopoJSON` decode (via `JSONValues`) into `GeoGeometry`, `MapProjection` (Web
    Mercator, fitted), `MapDiagram` (classed paths; colors in `ThemeBase`). STL (#116): `STL`
    (ASCII, line-based, tolerant of case and whitespace, 50k facets; normals recomputed),
    `STLProjection` (fixed isometric camera, fit, back-face culling, painter's sort, Lambert
    shade in 8 buckets), `STLDiagram` (a `<path class="peep-stl-sN">` per run of one shade in
    painter's order; colors in `ThemeBase`, `oklch(from currentColor …)`).
    `MarkdownNode.rewritingCodeBlocks` (AST) is the walk both code block passes share.
    Mermaid (#117) isn't a `DiagramKind`: `MermaidBlocks` only finds blocks (`mermaid`, any
    case) for `RenderedDocument.hasMermaidBlocks` (false with `diagrams` off); the HTML keeps
    the code block and only the app's viewer draws it.
    `DiagramWindowPage` is the page of the app's diagram window (one SVG over the theme,
    `ContentSecurityPolicy.diagramWindow`).
  - `AppOpening/`: what the CLI and the app agree on (M5; untrusted on the app's side).
    `AppOpenEvent` builds and reads the Open Documents event and its parameters
    (`AppOpenParameters`: `PepT` theme, `PepW` wait token in `+Wait`, with the
    `windowsClosed` notification name), and `StandardInputHandoff` writes, verifies, and takes
    the `cmd | peep` handoff file.
  - `QuickLook/`: what the Quick Look extensions render. `QuickLookConfiguration` (the
    settings the app publishes to the App Group `<team>.now.peep`, read with `published()`;
    untrusted on the extensions' side: a custom theme's CSS is checked again), `QuickLookPreview`
    (the page: fixed safety settings, `RemoteImagePolicy.blockAll` placeholders for every image
    but `data:`, `ContentSecurityPolicy.quickLook`, a 2 MB cap). No thumbnail extension: macOS 27
    never calls a third-party Markdown thumbnailer (its own text one wins; FB24481377).
  - `Generated/`, `*.generated.swift`: generator output (`make emoji`, `make html-entities`,
    `make vendor-highlightjs`); never edit by hand. `Vendor/` holds vendored sources with a
    MANIFEST and license; `Vendor/mermaid` (`make vendor-mermaid`, needs npm) is the one used
    as is, `mermaid.min.js` read from the app's Resources, with `NOTICES` for its bundled packages.
  - `Acknowledgements/`: `Acknowledgements` reads the third-party notices manifest (#85) and
    reflows license text (`paragraphs(of:)`) for the About panel.
- `Acknowledgements/` (repo root): `Acknowledgements.json` lists every bundled third-party
  component (name, use, license, `licenseFile` relative to the repo root, `licenseSource`, and the
  `vendor` folder or `package` identity it covers) plus the license texts not already in
  `Vendor/`. Copy a license from upstream (`gh api`), never retype it. `Acknowledgements/` and
  `Vendor/` ship as folders in the app's Resources; `AcknowledgementsTests` fails when a
  `Vendor/` folder, a `Package.resolved` pin, or a remote `project.yml` package lacks an entry
  (a resolved package that isn't shipped goes in its `notShipped`, with the reason).
- `App/`: the macOS app (module `PeepApp`), kept thin. AppKit lifecycle (`main.swift`,
  `AppDelegate`), SwiftUI for window content only. `About/AboutPanel` is App menu > About Peep:
  the standard panel with credits built in code from the bundled acknowledgements (no
  Credits.html). Feature folders: `ContentWidth/`, `Copy/`,
  `DefaultViewer/`, `Print/`, `RenderProgress/`, `Themes/`, `Zoom/` (each a small type plus its
  `DocumentWindowController+<Feature>.swift`). `Themes/ThemeSettings` holds the theme registry
  and the default for new windows; each window's theme is `DocumentWindowController.themeID`.
  `Themes/CustomThemeLibrary` watches the custom themes folder (`ThemeFolderWatcher`) and
  replaces the registry (`ThemeSettings.apply(_:)`). A window whose picked theme isn't
  registered shows Settings' default (`ThemeSettings.theme(forWindowThemeID:)`). The window
  resolves `themeID`: its View > Theme pick (`pickedThemeID`, the only theme restoration saves),
  else the document's `peep.theme` (`documentThemeID`, from `RenderedPage`), else Settings'
  default when it opened (`newWindowThemeID`).
  - `Settings/`: `SettingsWindowController` (App menu > Settings…, a toolbar-style
    `NSTabViewController` of SwiftUI panes), `SettingsModel` (wraps the existing stores:
    `ThemeSettings`, `OutlinePreference`, `ZoomSettings`, `ContentWidthSettings`, the default
    viewer; stores nothing itself), and `GeneralSettingsView`. A new setting is a store with
    `init(defaults:isPersistent:)`, a property and `set…` method on the model, and a row.
    `MarkdownSettingsView` (#55) is Settings > Markdown: default flavor, frontmatter display,
    Render diagrams (M7, `MarkdownSettings.rendersDiagrams`, published to Quick Look),
    built-in preprocessors (one row per `MarkdownSettings.optionalPreprocessors` entry), then
    the custom preprocessor (#57) and processor (#106) sections. `ReadingSettingsView` is
    Settings > Reading: how open documents behave (change highlights). General has no room to
    grow: CI's screen puts its last rows under the Dock (`UpdatesUITests`), so new settings go
    in another pane.
  - `QuickLook/`: `QuickLookConfigurationPublisher` writes `QuickLookConfiguration` to the App
    Group's defaults on launch and on each `ThemeSettings` / `MarkdownSettings` change (custom
    theme files included); off under tests and without a team (`PEEP_APP_GROUP` in
    `Config/Shared.xcconfig`, the `PeepAppGroup` Info.plist key). Quick Look's theme is
    `ThemeSettings.quickLookThemeID` (`nil` follows the default), Settings > Quick Look's picker
    (`Settings/QuickLookSettingsView`).
  - `WikiLinks/`: `DocumentWikiLinks` (a per-render `FolderWikiLinkResolver` for a document,
    used by `DocumentContent` and Copy as HTML) over PeepCore's `FileSystemFolderReader`.
  - `MarkdownSettings/`: `MarkdownSettings` (the store: default flavor id, frontmatter
    display, built-in preprocessors; one change notification) and `MarkdownPreferences` (the
    value a render takes; `apply(to:)` sets `RenderOptions`). Unlike window defaults these
    apply to open documents: `MarkdownDocument` follows the store and re-renders in place, and
    `DocumentContent.preferences` records what a page was rendered with.
  - `CustomProgram/` (#57, #106): the custom preprocessor and processor share one store, model,
    bar, and Settings section, each built for a `CustomProgramKind` (PeepCore; app text and
    accessibility prefixes in `CustomProgramKind+App`). `CustomProgramSettings` (store: on/off,
    executable, arguments, the session's `lastRun`; `.preprocessor` and `.processor` shared
    instances with their own `Keys`, in memory under tests, or set by `-PeepUITestPreprocessor`
    / `-PeepUITestProcessor`), `CustomProgramModel` (Settings' model: the enable warning, the
    Open panel), `DocumentContent.rendering(_:of:preferences:)` (the async render: runs the
    preprocessor, then the processor on the body; each failure falls back, with
    `preprocessorError` / `processorError`), and `CustomProgramFailureBar` (both bars share
    one `safeAreaInset` in `DocumentView`: another inset kept closed windows' documents alive).
    The settings reach renders as `MarkdownPreferences.customPreprocessor` / `customProcessor`
    (`MarkdownDocument.renderPreferences`), so a change re-renders open documents like any
    Settings > Markdown change. `DocumentContent.processedHTML` is the processor's raw output;
    pages and Copy as HTML sanitize it. The section view is `Settings/CustomProgramSection`.
  - `CommandLineTool/` (#70): App menu > Install / Repair / Uninstall Command Line Tool….
    `CommandLineToolInstaller` (the rules over an injected folder and app: state, atomic
    install, uninstall, and the constant privileged shell scripts; an `Item` per linked file,
    the hook for #71), `PrivilegedRunning` (`AppleScriptPrivilegedRunner`, values passed as
    Apple event parameters), `CommandLineToolLocation` (`~/.local/bin`, `/usr/local/bin`, or
    the UI-test folder; `LoginShellPath`), and `CommandLineToolController` (menu state, alerts).
    `HomebrewCask` (#84): a prefix whose `Caskroom/peep` exists and whose `bin/peep` is our
    link is Homebrew's; the item becomes Command Line Tool Installed by Homebrew… (an alert
    only), and that folder is never offered for install or uninstall. No prefixes under tests.
  - `CollapsibleSections/`: `CollapsibleSectionsSettings` (Settings > General's "Click headings
    to collapse sections", off by default, every window live; `-PeepUITestCollapsibleSections
    YES` under UI tests). The page side is `App/Scripts/CollapsibleSections.js`
    (`peepSections`, also used by `DocumentBridge.js` and `FindInPage.js` to skip and unfold
    folded blocks), via `WebViewCoordinator+Sections` and
    `DocumentWindowController+CollapsibleSections.swift`; View > Collapse/Expand All Sections is
    `SectionsMenu`. The `data-peep-folded` rule is in `ThemeBase`.
  - `ChangeHighlights/`: `ChangeHighlightsSettings` (Settings > Reading's "Highlight changes
    when a file is saved", `Settings/ReadingSettingsView`, off by default;
    `-PeepUITestChangeHighlights YES` under UI tests; and its supplemental "Scroll to the first
    change", `scrollsToChanges`, applied only while highlights are on, `scrollsOnChange`;
    `-PeepUITestScrollToChanges YES`: after marking, `peepChanges.scrollToFirst` scrolls to the
    first mark unless one is on screen).
    While it is on, `LiveReloader` diffs the old and new `renderedSource` off the main actor
    (not for a custom processor's page, which has no source lines) and passes
    `MarkdownDocument.setContent(_:changes:)` a `SourceChanges` (`contentChanges`; any other
    `setContent` clears it). The window marks it after each load or swap
    (`DocumentWindowController+ChangeHighlights.swift`, `WebViewCoordinator+ChangeMarks`); the
    page side is `App/Scripts/ChangeMarks.js` (`peepChanges`: bars in their own layer outside
    the article, fading once seen, off-screen counts posted to the `changeMarks` handler). The
    status bar's `ChangesItem` shows those counts and scrolls to the next change. The
    `data-peep-change` rules are in `ThemeBase`.
  - `RaiseOnChange/`: `RaiseOnChangeSettings` (Settings > Reading's "Bring the window to the
    front when a file is saved", off by default; `-PeepUITestRaiseOnChange YES` under UI tests).
    `LiveReloader` passes `MarkdownDocument.setContent(_:changes:textChanged:)` whether the text
    changed; while the setting is on, that sets `raiseTarget` (the document's window nearest the
    front; any other `setContent` clears it), and that window's display task calls
    `bringForwardAfterReload()` (`DocumentWindowController+RaiseOnChange.swift`: unminimize,
    make key, `NSApp.activate(ignoringOtherApps: true)`: the cooperative `NSApp.activate()` is
    refused from the background) after marking changes.
  - `Updates/` (#81): Sparkle 2 (app target only). `SoftwareUpdating` (what the menu and
    Settings use; fakes in tests), `SparkleUpdater` (`SPUStandardUpdaterController`, started from
    `AppDelegate.applicationDidFinishLaunching`; channels), `InactiveUpdater` (in memory, never
    checks), and `SoftwareUpdates` (which launch gets which: hosted tests, UI tests, and
    `PEEP_LAUNCH_TIMING` never get Sparkle; Debug only with `-PeepUpdateFeedURL <url>`, for a
    local test appcast; Release always). App menu > Check for Updates… is `UpdatesMenu`;
    Settings > General's rows go through `SettingsModel.updater`, which stores nothing (Sparkle
    owns the settings). The public key is `SPARKLE_PUBLIC_ED_KEY` in `Config/Shared.xcconfig`
    (Release fails on the placeholder); Sparkle's `generate_keys`, `sign_update`, and
    `generate_appcast` are in `build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin`.
  - `Document/`: `MarkdownDocument` (`NSDocument`, viewer only) owns `DocumentContent` (source
    plus `RenderedPage`, and the remote-images variant). `read(from:ofType:)` reads and decodes
    on main (so open errors stay NSDocument's) and renders off the main actor
    (`render(_:of:)`; tests await `pendingRender`), so `content` is `nil` until the first render
    lands; a newer read, `setContent`, or `close()` drops and cancels a render in flight
    (stopping a custom preprocessor run). Every load and
    revert goes through `setContent(_:)`, which tells each `DocumentWindowController`
    (and re-renders content made with outdated Markdown settings, #55).
    `DocumentController` (the shared `NSDocumentController`) finds open files by identity,
    skips gone files on restore, types extensionless text files (`ExtensionlessText`) as
    plain text, and turns a verified standard input handoff into an untitled
    `MarkdownDocument(standardInput:)` (#68); its `canOpen(_:)` is the one rule for the Open
    panel and drops. `DocumentOpener` applies an Open Documents event's Peep parameters
    (`--theme` as each window's pick, `--wait` tokens through `WindowWaits`, #69): on Launch
    Services paths `DocumentController.openDocument` hands it files whose parameters
    `OpenDocumentsEventTap` recorded (`OpenDocumentsEventLog`; AppKit never calls
    `application(_:open:)` for a document-based app, so don't add it back), and the direct
    `Peep/odoc` handler calls `open(_:parameters:)`.
  - `Find/`: `FindInPage` (find state and commands, tested with a fake host), `SharedFindQuery`
    (the system find pasteboard), and `FindBar`
    (SwiftUI bar; the field is an `NSSearchField` whose field editor passes Edit > Find
    commands on). The page side is `App/Scripts/FindInPage.js` via `WebViewCoordinator+Find`.
  - `LiveReload/`: `FileWatcher` (kqueue by path, debounced; watches the nearest existing
    ancestor while the folder is gone) and `LiveReloader` (reads and
    renders off the main actor, drops stale renders, sets `MarkdownDocument.fileStatus`). Live
    reload bypasses `NSDocument.revert`; the window swaps content in place with
    `WebViewCoordinator.updateContent(with:baseURL:)`, which keeps the reading position.
  - `Outline/`: `OutlineViewController` (the sidebar's `NSOutlineView`) and `OutlinePreference`
    (default visibility). The window fills it after the first page paints (#58), then on each
    display.
  - `StatusBar/`: the strip along the bottom of the window (`DocumentView`'s bottom inset):
    `StatusBar` (the items, leading; first `WordCountItem`, from `RenderedPage.wordCount`, then
    `ChangesItem` while change marks are out of view; then `PinToggleItem` and
    `OutlineToggleItem`, trailing, which replaced the toolbar: windows have none), `StatusBarModel` (the window's visibility, and the outline's and pin for the toggles), and
    `StatusBarPreference` (default visibility, shown). View > Show/Hide Status Bar (⌘/) is
    `DocumentWindowController+StatusBar.swift`; a new item is a view in `StatusBar`.
  - `WindowPin/`: `WindowPinPreference` (Settings > General's "Keep new windows on top"; the
    window's pin never changes it). The window side is `DocumentWindowController+Pin.swift`:
    `isPinned` sets the `.floating` level, a pin belongs to the whole tab group (a tab joining a
    pinned group adopts it on becoming key, `adoptTabGroupPin()`), restored per window. Window >
    Pin Window (⌥⌘P) is `WindowPinMenu`.
  - `RenderProgress/`: `RenderProgress` (#58: the delayed indicator's state, 300 ms by default,
    injectable) and `RenderProgressIndicator` (the overlay: centered over the blank page before
    the first page loads, small in the corner during re-renders). The window feeds it from
    `isWaitingForFirstPage` and `MarkdownDocument.isRendering` (a render or live reload in
    flight; `updateRenderActivity()` tells each window).
  - `Window/`: `DocumentWindowController` (one per window, in the responder chain; feature
    actions go in `DocumentWindowController+<Feature>.swift`, menu validation in the one
    `validateMenuItem` switch in `+Outline.swift`), `DocumentWindow` (restorable state),
    `DocumentView` (SwiftUI root: find bar, file status and remote image bars, link status),
    `WindowChrome` (the theme colors of the titlebar border and status bar; the titlebar is
    transparent over the theme-colored window background, `applyWindowChrome()` also fills the
    outline sidebar and its edge; it never changes the window's appearance, and when the theme
    background's darkness doesn't match it, forces only the titlebar container and sidebar).
    Dynamic theme `NSColor`s are named by their colors: same-named dynamic colors are equal, and
    AppKit ignores an equal color.
  - `WebView/`: `WebViewCoordinator` owns the `DocumentWebView` (drops, context menu trimming):
    `prepareForFirstLoad()` (a blank page while the first render runs), `load`, `updateContent`,
    and the async bridge (`readingPosition()`, `scroll(toSourceLine:)`,
    `scroll(toFragment:)`). `WebViewPrewarmer` starts the first window's web view at launch
    (#40). `WebViewConfiguration` holds preferences and user scripts;
    `LocalResourceSchemeHandler` serves `peep-doc` images; `+Navigation.swift` applies
    `LinkPolicy`. Mermaid (#117): `DiagramScripts` (the `peep-diagrams` world, no message
    handlers ever; its source is `Vendor/mermaid/mermaid.min.js` plus `MermaidDiagrams.js`) and
    `+Diagrams.swift` (evaluated once per page, only when `RenderedPage.hasMermaidBlocks`, after
    `load`; redrawn after `updateContent`/`replaceContent` swaps and on theme or appearance
    darkness changes; serialized in `pendingDiagramRender`, which the window awaits for a mermaid
    page before scrolling). Diagram controls: `App/Scripts/DiagramControls.js` (app world: a
    viewport, zoom/pan transform, buttons; a MutationObserver attaches them to new figures)
    posts Open in Window to `diagramWindow` (`+DiagramWindow.swift`), and
    `App/Diagrams/DiagramPanelController` shows the SVG in a JavaScript-free panel
    (`DocumentWindowController+DiagramWindow.swift`; an `NSPanel` is a Dialog to UI tests).
    Render diagrams off makes `hasMermaidBlocks` false
    (`RenderOptions.diagrams`), and the Settings re-render swaps the code blocks back in.
  - `Scripts/`: bundled JS run only in `AppScripts.world` (but `MermaidDiagrams.js`, in
    `DiagramScripts.world`); pass values as arguments, never splice them into source.
  - `Performance/`: `LaunchTiming`, launch milestones that `scripts/measure-cold-open` reads
    (on only with `PEEP_LAUNCH_TIMING` set; kept in Release, which is what it measures).
  - `Menus/`: `MainMenu` builds the menu bar in code. A feature adds a `MenuContribution` type
    in its own file plus one line in `MainMenu.contributions`. AppKit inserts Open Recent and
    the Window menu's items itself; don't build them.
- `Extensions/`: the Quick Look extension, embedded in `Contents/PlugIns`, sandboxed, App Group
  only (`Preview/Preview.entitlements`; `scripts/package-release` fills in the group).
  `Preview/PreviewProvider` (`PeepQuickLook`, a data-based `QLPreviewProvider` returning
  `QuickLookPreview`'s HTML). Keep it thin; logic goes in
  `PeepCore/QuickLook`. Test by hand: `pluginkit -mAvvv -i now.peep.Peep.quicklook` shows which
  copy is registered (Debug and Release collide), `qlmanage -r` and `qlmanage -r cache` reset.
- `CLI/`: ArgumentParser `peep` tool, embedded at `Peep.app/Contents/Helpers/peep`.
  `CLI/PeepCLIKit` (library) is the command: `PeepCommand` (parse, cross-group `validate()`,
  mode pick, `execute(in: CLIEnvironment)`) plus one `@OptionGroup` file per concern
  (`InputOptions`, `OutputOptions`, `ThemeFlavorOptions`, `RenderFlagOptions`,
  `PreprocessorOptions`, `ProcessorOptions`, `AppOpenOptions`; the two program groups share
  `CustomProgramCommand`), `PeepCommand+HTML` (headless output),
  `PeepCommand+App` and `AppOpening` (opening in the app), `ExitStatus` (sysexits codes, listed
  in `--help`), and `CLIError` (one `peep: …` stderr line plus a status). `CLI/Main` is the
  executable (SwiftPM `PeepCLI`, Xcode `peep-cli`) and only calls `PeepCommand.main()`. A new flag
  goes in its concern's group file; never read the process's streams directly (use
  `CLIEnvironment`). Completions and the man page (#71) are generated from the command, so a
  flag needs nothing more (give a path or id value a `completion:`). Text `--help` and the man
  page share lives in `HelpText` (overview, examples) and `ExitStatus.entries`; `ManualPage`
  finishes generate-manual's page with the hand-written sections, run by the `CLI/ManualTool`
  build tool (`PeepManualTool`, not shipped) from `make cli-docs`. Opening in the app:
  `WorkspaceAppOpener` (Launch Services, or the direct event to our running copy) with
  `AppLocator` (which app), `WindowsClosedWaiter` and `DarwinNotification` (`--wait`), and the
  stdin handoff; `InterruptCancellation` turns signals into cancellation around a preprocessor
  run.
- `Tests/PeepCLITests`: CLI tests under `swift test`. `CLIHarness.run` parses and runs the command
  in-process against a fake `CLIEnvironment` (captured streams, `RecordingAppOpener`);
  `CLIBinary.run` runs the built `peep` with stdin and captures stdout, stderr, and the status.
  `TempFolder` is a per-test folder; fixtures are in `Fixtures/`. `ReadmeExampleTests` runs
  every `peep` command in the README's `sh` blocks (#72): a README example must be one its
  shell reader (`Support/ReadmeExamples.swift`) understands, and must work. Tests reading the
  generated man page and completions need `PEEP_CLI_DOCS` (`make test-core` sets it).
- `Tests/PeepCoreTests`, `AppTests/`: Swift Testing (`import Testing`, `@Test`, `#expect`).
  `AppTests/Support/`: `DocumentWindowTestCase` (windows over temp files and throwaway
  settings), `ThrowawayDefaults` (a per-test `UserDefaults` suite in a temp folder; never use
  `UserDefaults(suiteName:)` with a plain name, which leaves a plist in ~/Library/Preferences),
  `MainThreadHeartbeat` (main-thread stalls by CPU time), `expectTiming` (`MainThreadTiming`: main-thread
  timing bounds, strict locally, report-only on CI via `TEST_RUNNER_PEEP_TIMING_REPORT_ONLY`), `SnapshotImage`, `LoopbackServer`,
  `PreprocessorScripts` (custom preprocessor scripts plus a leaked-process check).
  `StressTests` (+`Themes`, `ZoomWidth`, `Preprocessor`, `Markdown`, `CommandLine`) is the crash and hang suite; run it
  under ASan and TSan at each milestone close-out (`-enableAddressSanitizer YES` / `-enableThreadSanitizer YES`).
- `AppUITests/`: XCTest UI tests (see "UI tests" below). `App/Testing/UITestHooks.swift` holds
  the Debug-only launch hooks they use.
- `docs/THEMES.md`: the end-user theme authoring guide, with `docs/example-theme.css` and
  `docs/github-soft-dark.css` (an `extends: github` example).
  `ThemeGuideTests` loads the example and checks the guide's snippets, limits, and error
  messages; a change to custom theme behavior updates the guide.
- `Tests/PeepCoreTests/Fixtures/spec`: vendored CommonMark/GFM spec examples, run in
  `RenderOptions.spec` mode. `exceptions.json` lists known failures (`pending #N` or `permanent`);
  a feature issue deletes its `pending` entries once they pass (the test fails on stale entries).
- `Tests/PeepCoreTests/Fixtures/flavors/<id>/`: per-flavor corpus (`FlavorCorpusTests`), `.md`
  inputs and recorded `.html` (`PEEP_RECORD_SNAPSHOTS=1`); one folder per registered flavor. A
  feature that changes a flavor's output adds fixtures to it.
- `Tests/PeepCoreTests/Fixtures/flavors/<id>`: per-flavor corpus (`FlavorCorpusTests`,
  `PEEP_RECORD_SNAPSHOTS=1`). `Fixtures/github/alerts.md` is github.com's alert rules from
  `gh api markdown` (mode gfm), compared normalized (see that folder's README).
- `Tests/PeepCoreTests/Fixtures/github`, `.../corpus`: GitHub reference output (refresh with
  `scripts/update-github-fixtures`, manual, needs auth) and Peep snapshots
  (`PEEP_RECORD_SNAPSHOTS=1`). Corpus exceptions live in `corpus.json`.
- `AppTests/Snapshots/macOS-<major>/`: visual regression references for the bundled themes
  (`ThemeSnapshotTests`: showcase fixture, each theme light/dark/print, real WebKit PDFs
  rasterized at 1 px per point). One set per macOS major (CI is macOS 26). After an intended
  theme change, `make record-theme-snapshots` on each OS and review the PNG diff; macOS 26
  references come from CI's `theme-snapshots` artifact (`recorded/`). Mismatches write
  actual/reference/diff PNGs to `build/theme-snapshots/` (CI uploads it).
- `project.yml`: XcodeGen spec. Never commit `Peep.xcodeproj`; edit `project.yml` instead.
- `Packaging/homebrew/peep.rb` (#84): the source of the tap's `Casks/peep.rb`
  (`itspriddle/homebrew-brews`); `scripts/render-cask` fills in `version` and `sha256`. A
  change to the bundle layout (helper, man page, completions) or to where the app stores files
  (the `zap` list) updates it. Check it with `brew style` and `brew audit --cask --strict` in a
  scratch tap (`brew tap-new`, `brew trust`, then untrust and untap).
- `CONTRIBUTING.md`, `SECURITY.md` (private reports via GitHub security advisories), and
  `.github/ISSUE_TEMPLATE/` (bug and feature forms; `config.yml` sends security reports to the
  advisory form): the human-facing versions of this file's rules; keep them in step.
- `Config/Shared.xcconfig`: shared settings. `Config/Local.xcconfig` (gitignored) holds
  `DEVELOPMENT_TEAM`; never commit it or hard-code the team ID.
- `scripts/package-release` (#82, `make release`): builds Release ad hoc, then signs every
  Mach-O inside out with the Developer ID identity (Sparkle's XPC services, `Autoupdate`,
  `Updater.app`, the framework, the helper, the app), checks each has the hardened runtime and
  a secure timestamp, makes and signs the DMG, notarizes and staples it, and smoke-tests the
  packaged `peep`. A new nested binary fails its Mach-O check until the script signs it.
  `docs/RELEASING.md` has its environment variables and the release steps.
- `scripts/release-appcast` (#83): `generate_appcast` over the previous release's
  `appcast.xml` (its signature verified, items kept) plus the new stapled DMG; refuses a version
  already in the feed or a key that isn't the app's, then verifies the feed and item signatures.
- `.github/workflows/release.yml` (#83): a `vX.Y.Z` tag runs `check` (no secrets) → `build`
  (`release` environment: package-release, release-appcast) → `publish` (draft, upload,
  publish) → `site` (calls `deploy-site.yml`) and `cask` (`release` environment: render-cask,
  push to the tap's `master`). `docs/RELEASING.md` has the run book.
- `Site/` (peep.now, Astro static output with zero client JS, Tailwind; Vite+ `vp` for format,
  lint, and tests; Cloudflare Workers static assets; `deploy-site.yml`): `vp check`, `vp test`,
  `vp run build` (`astro check`, `astro build`). `postinstall` runs `astro sync`, which writes
  the gitignored `.astro/` types that `astro:content` imports need (`vp check` fails without them). `public/_headers`' CSP allows nothing inline,
  so `astro.config.ts` never inlines stylesheets, pages add no `<script>`, and code blocks use
  Prism classes (token colors in `src/style.css`), not Shiki's inline styles. Doc pages render
  files from the repo's `docs/` in place (`src/content.config.ts` lists each one; never move
  them, the app's tests read them); `src/lib/remark-repository-links.ts` points their relative
  links at GitHub, or at the page for a file in `publishedDocs` (`src/lib/repository.ts`). A
  doc edit reaches peep.now on the next deploy. The build ends with `scripts/fetch-release.ts`
  (`scripts/release.ts`), which copies the latest published GitHub Release's signed
  `appcast.xml` into `dist/` and writes `dist/_redirects` (`/download` → that release's
  `Peep-X.Y.Z.dmg`, 302); neither exists before the first release (a real 404, never HTML).
  The site never signs anything.

## Conventions

- Swift 6 language mode, strict concurrency, macOS 15 minimum.
- Lint and format must pass with zero violations; swift-format owns layout, SwiftLint owns smells.
- No force unwraps; prefer failable APIs (e.g. `String(bytes:encoding:)`) and throw on bad input.
- Security defaults from `docs/VISION.md` are requirements: strict CSP, no remote content, JS off
  or bundle-only, sanitize raw HTML, user scripts are opt-in.
- Bundle ID `now.peep.Peep` lives in `PRODUCT_BUNDLE_IDENTIFIER_BASE`,
  `PeepCommand.appBundleIdentifier`, and the exported UTI `MarkdownContentTypes` (an app test
  checks it); keep them in sync. Change the version only with
  `scripts/bump-version` (`MARKETING_VERSION`, `PeepInfo.version`, `CURRENT_PROJECT_VERSION`);
  `scripts/check-version` (in `make lint`) fails if they disagree.
- Verify a dependency exists (and its latest version) before adding it.

## UI tests

- `AppUITests` (XCTest; Swift Testing has no UI API) drives the built app. Every M2+ feature with
  a user-facing flow adds a test here. Fixtures live in `AppUITests/Fixtures/` (a folder
  reference; `Fixtures.url(named:)`).
- Use `PeepUITestApp` (`AppUITests/Support/`): `launch(openingFixture:)`, `waitForWindow(titled:)`,
  `webView(in:)`, `waitForRenderedText(_:in:)`. Add feature helpers in
  `Support/PeepUITestApp+<Feature>.swift`. Classes are `@MainActor final class ...: XCTestCase`.
- Launch hooks (`UITestHooks`, `#if DEBUG` only, compiled out of Release): `-PeepUITesting YES`
  skips the launch Open panel and suppresses first-run prompts (features with a first-run prompt
  must check `UITestHooks.suppressesFirstRunPrompts`); `-PeepUITestOpen <abs path>` (or a
  plist array, `launch(openingFixtures:)`) opens documents at launch; `-PeepUITestThemesFolder
  <abs path>` reads custom themes from a temp folder (UI tests without it load none, and hosted
  unit tests never load them); `-PeepUITestPreprocessor <abs path>` starts with that custom
  preprocessor on; `-PeepUITestRaiseOnChange YES` starts with raising windows on save on;
  `-PeepUITestRenderDelay <seconds>` holds up every render (to see the
  slow-render indicator without a slow script); `-PeepUITestCommandLineToolFolder <abs path>`
  is the only folder Install Command Line Tool… offers (none without it). UI tests that run the
  CLI (`PeepUITestApp+CommandLine`, `+Wait`) use the built app's helper; the runner is
  sandboxed, so Launch Services refuses it and the CLI falls back to the direct event
  (`AppUITests.entitlements` allows it), fixtures are copied to temp first, and standard input
  comes from a file, never a pipe. Preprocessor scripts are executable fixtures
  (`Fixtures/preprocessors/`): files the sandboxed runner writes are quarantined and won't
  execute (`EPERM`). Tests never add to Open Recent. `PeepUITestApp.launch` also passes `-ApplePersistenceIgnoreState YES` unless
  `restoresState: true`; the restoration UI test writes real saved state, so it runs only with
  `TEST_RUNNER_PEEP_UI_TEST_RESTORATION=1 make test-ui` (CI sets it).
- The UI test runner must be code signed: `make test-ui` ignores `SIGN` and signs with the team
  in `Config/Local.xcconfig`, else ad hoc. Never run UI tests unsigned (Gatekeeper pops a
  "can't run" dialog for every attempt).
- Local setup: the app that runs `make test-ui` (Terminal, iTerm, Claude Code's host) needs
  System Settings > Privacy & Security > Developer Tools, or Gatekeeper kills the runner
  ("Test crashed with signal kill before establishing connection"; log shows "Gatekeeper policy
  blocked execution"). The first run asks to allow `AppUITests-Runner` Accessibility access.
- Debugging: failures leave `build/AppUITests.xcresult` (screenshots, logs, UI hierarchy);
  `open build/AppUITests.xcresult`. Run one test with
  `xcodebuild ... test -only-testing:AppUITests/SmokeUITests/testOpensFixtureWithTitleAndRenderedText`
  or from Xcode (`make generate`, open `Peep.xcodeproj`, scheme `Peep`). `app.debugDescription`
  prints the accessibility tree. CI uploads the result bundle on failure.
- The Xcode app target is `PeepApp` (product `Peep.app`): a target named `peep` collides with the
  SwiftPM `peep` executable, and the UI test runner then launches the CLI.

## Workflow

- GitHub: `itspriddle/peep` (public). Each roadmap milestone is a GitHub milestone with
  issues.
- One branch per issue (Conventional Branch, e.g. `feature/gfm-tables`), Conventional Commits
  (see `.claude/skills`). Issue branches merge into a milestone integration branch
  (e.g. `feature/m1-core-rendering`), which goes to `main` as one PR that must pass CI.
- After an issue lands, post a handoff comment (API changes, gotchas, deviations, deferred items)
  on the next issue or the milestone's tracking issue.
- When a milestone closes, update its status in `docs/ROADMAP.md`.
- Releases: `scripts/bump-version` in a PR, merge, then a `vX.Y.Z` tag on `main` (maintainer
  only) runs `release.yml`; approve its two `release` deployments. Never tag, publish, or
  push to the tap by hand without the maintainer (`docs/RELEASING.md`).
