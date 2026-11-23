/// The base layer every page gets under its theme: the rules viewer features depend on.
///
/// It sits in the first cascade layer (`ThemeLayer.base`). Ordinary declarations here are
/// defaults any theme may override (such as GitHub alerts' left rule and title layout, #52, so a
/// custom theme without `extends` still shows them as callouts). Declarations marked
/// `!important` are protected: an important declaration in an earlier layer beats important
/// declarations in later layers and unlayered CSS, so no theme (bundled or custom, layered or
/// not) can undo them. The sanitizer strips `style` attributes, so element-attached styles can't
/// either. Protected:
///
/// - `.sr-only` (visually hidden text for assistive technology);
/// - find highlights (`::highlight(peep-find)`, `::highlight(peep-find-current)`, #25), never
///   printed;
/// - the blocked remote-image placeholder's visibility (#20) (its look is a default);
/// - folded collapsible sections (`[data-peep-folded]`, the app's `CollapsibleSections.js`)
///   staying hidden (the chevron's look is a default);
/// - change marks (`[data-peep-changes]`, the app's `ChangeMarks.js`) staying out of the way:
///   positioned over the page, never hit, never printed (their color and fade are defaults);
/// - a drawn mermaid block's code (`pre[data-peep-diagram="rendered"]`, the app's
///   `MermaidDiagrams.js`) staying hidden behind its diagram (the error note's look is a default);
/// - diagram zoom controls (`[data-peep-diagram-controls]`, the app's `DiagramControls.js`) and
///   zoom never printed (the controls' look is a default);
/// - diagrams' look (`.peep-diagram`, the map and STL classes; M7) is a default;
/// - GitHub's `#gh-dark-mode-only` / `#gh-light-mode-only` hiding (`ColorModeImage`);
/// - structural print rules (#26, #38): light color scheme, no page background, full width,
///   nothing clipped, no anchor icons, sensible page breaks. External link targets written out
///   on paper and widow/orphan control are defaults.
///
/// Print contract for themes (#38): paper is always light. Dark colors belong under
/// `@media screen and (prefers-color-scheme: dark)`, so print uses the light ones. The page
/// background never prints (protected `print-color-adjust: economy` on `:root` and `body`), and
/// neither do element backgrounds unless the theme opts an element in with
/// `print-color-adjust: exact` (bundled themes do for code, keys, marks, and tables).
public enum ThemeBase {
    public static let css = """
        :root { color-scheme: light dark; }
        .sr-only {
          position: absolute !important; width: 1px !important; height: 1px !important;
          padding: 0 !important; margin: -1px !important; overflow: hidden !important;
          clip: rect(0, 0, 0, 0) !important; white-space: nowrap !important; border: 0 !important;
        }
        /* Blocked remote images (#20): a labeled placeholder. Themes may restyle it, not hide it. */
        .remote-image {
          display: inline-flex; flex-direction: column; justify-content: center; align-items: center;
          box-sizing: border-box; max-width: 100%; min-height: 1.75em; padding: 2px 8px; overflow: hidden;
          vertical-align: middle; border: 1px dashed #d1d9e0; border-radius: 6px;
          color: #59636e; background: #f6f8fa; font-size: 0.75em; line-height: 1.3; text-align: center;
        }
        .remote-image { display: inline-flex !important; visibility: visible !important; }
        .remote-image-host { opacity: 0.75; }
        /* GitHub alerts (#52): a left rule and the icon beside the title, so they read as callouts in
           a theme that doesn't style them. Colors are the theme's (the rule and icon follow the text). */
        .markdown-alert { margin: 0 0 1em; padding: 0 1em; border-left: 0.25em solid; }
        .markdown-alert > :first-child { margin-top: 0; }
        .markdown-alert > :last-child { margin-bottom: 0; }
        .markdown-alert-title { display: flex; align-items: center; font-weight: 600; line-height: 1.25; }
        .markdown-alert-title svg { flex: none; margin-right: 0.5em; fill: currentColor; }
        /* Diagrams (M7): maps and STL models the renderer draws (`MapDiagram`, `STLDiagram`: a
           `figure.peep-diagram` around an inline SVG). Paths have classes, never colors: they take
           the text color, so every theme works light, dark, and print. Themes may restyle all of it. */
        .peep-diagram {
          position: relative; box-sizing: border-box; margin: 0 0 16px; padding: 24px 16px;
          border: 1px solid color-mix(in srgb, currentColor 20%, transparent); border-radius: 6px;
        }
        .peep-diagram > svg, .peep-diagram-viewport > svg {
          display: block; box-sizing: border-box; max-width: 100%; height: auto; margin: 0 auto;
        }
        /* Maps and models fill the column; mermaid keeps its own inline max-width (its natural
           size, never scaled up). */
        .peep-diagram svg:is(.peep-map, .peep-stl) { width: 100%; }
        /* Zoom and pan (the app's DiagramControls.js): the SVG is scaled and moved inside a
           viewport that keeps its unzoomed size, so zooming never moves the page. The controls
           show while the figure is hovered or focused. Never set by documents (the sanitizer
           drops `data-` attributes); never printed. */
        .peep-diagram-viewport { overflow: hidden; }
        .peep-diagram-viewport > svg { transform-origin: 0 0; }
        .peep-diagram-viewport[data-peep-zoomed] { cursor: grab; }
        .peep-diagram-viewport[data-peep-dragging] { cursor: grabbing; }
        [data-peep-diagram-controls] {
          position: absolute; inset: 8px 8px auto auto; display: flex; flex-direction: column;
          align-items: flex-end; gap: 6px; opacity: 0; transition: opacity 120ms ease-out;
        }
        .peep-diagram:is(:hover, :focus-within) > [data-peep-diagram-controls] { opacity: 1; }
        .peep-diagram-pad { display: grid; grid-template-columns: repeat(3, 28px); gap: 4px; }
        [data-peep-diagram-controls] button {
          display: inline-flex; align-items: center; justify-content: center; box-sizing: border-box;
          width: 28px; height: 28px; margin: 0; padding: 0; border-radius: 6px; font: inherit;
          color: inherit; cursor: pointer;
          border: 1px solid color-mix(in srgb, currentColor 25%, transparent);
          background: color-mix(in srgb, Canvas 85%, currentColor 15%);
        }
        [data-peep-diagram-controls] button:hover { background: color-mix(in srgb, Canvas 75%, currentColor 25%); }
        [data-peep-diagram-controls] svg { width: 16px; height: 16px; fill: currentColor; }
        @media (prefers-reduced-motion: reduce) { [data-peep-diagram-controls] { transition: none; } }
        .peep-map-area {
          fill: currentColor; fill-opacity: 0.15; stroke: currentColor; stroke-width: 1.5;
          stroke-linejoin: round; vector-effect: non-scaling-stroke;
        }
        .peep-map-line {
          fill: none; stroke: currentColor; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round;
          vector-effect: non-scaling-stroke;
        }
        .peep-map-point { fill: currentColor; fill-opacity: 0.8; stroke: none; }
        /* STL shades, darkest (s0) to lit (s7): opaque, at a fixed lightness in the text color's
           hue, so a model reads the same on a light or dark page and on paper (gray where relative
           colors aren't supported). The stroke hides seams between facets. */
        .peep-stl path { stroke-width: 0.75; stroke-linejoin: round; }
        \(stlShadeRules)
        /* Wiki links (#53) to a missing page have no href, so themes style them as plain text
           (`a:not([href])`); a dashed underline keeps them distinguishable. */
        .wikilink-missing { border-bottom: 1px dashed; cursor: default; }
        /* Collapsible sections (the app's CollapsibleSections.js, while Settings turns them on): a
           folded block is hidden, and a top-level heading shows a chevron after its text on hover
           or focus, and always while collapsed. Never set by documents (the sanitizer drops
           `data-` attributes). */
        [data-peep-folded] { display: none !important; }
        /* Mermaid diagrams (#117, the app's MermaidDiagrams.js): a drawn block's code stays in the
           page, hidden, after its figure; one mermaid couldn't draw shows a note after it. */
        pre[data-peep-diagram="rendered"] { display: none !important; }
        .peep-diagram-error { margin-top: -0.5em; font-size: 0.85em; opacity: 0.75; }
        [data-peep-sections] .markdown-body > :is(h1, h2, h3, h4, h5, h6) { cursor: pointer; }
        [data-peep-sections] .markdown-body > :is(h1, h2, h3, h4, h5, h6)::after {
          content: "\\25BE"; display: inline-block; margin-left: 0.4em; font-size: 0.6em;
          font-weight: normal; vertical-align: middle; opacity: 0; color: currentColor;
        }
        [data-peep-sections] .markdown-body > :is(h1, h2, h3, h4, h5, h6)[data-peep-collapsed]::after {
          content: "\\25B8"; opacity: 0.6;
        }
        [data-peep-sections] .markdown-body > :is(h1, h2, h3, h4, h5, h6):is(:hover, :focus-visible)::after {
          opacity: 0.6;
        }
        /* Change marks (the app's ChangeMarks.js, while Settings turns them on): a bar beside each
           block a live reload changed and a short rule where text was deleted, in their own layer
           outside the article. They fade once seen. Never set by documents (the sanitizer drops
           `data-` attributes), never printed. */
        [data-peep-changes] {
          position: absolute !important; top: 0 !important; left: 0 !important; width: 0 !important;
          height: 0 !important; overflow: visible !important; pointer-events: none !important;
        }
        [data-peep-change] {
          position: absolute !important; pointer-events: none !important; width: 3px; border-radius: 1.5px;
          background: #0969da; background: -apple-system-control-accent; transition: opacity 800ms ease-out;
        }
        [data-peep-change="before"], [data-peep-change="after"] { width: 12px; height: 2px; margin-left: -9px; }
        [data-peep-change][data-peep-fading] { opacity: 0; }
        @media (prefers-reduced-motion: reduce) { [data-peep-change] { transition: none; } }
        /* Find in page (the app's find bar): every match, and the current one. Never printed. */
        ::highlight(peep-find) { background-color: rgb(255 214 0 / 0.4) !important; }
        ::highlight(peep-find-current) { background-color: #ff9632 !important; color: #1f2328 !important; }
        /* Dark colors are for the screen only: paper is always printed with the light colors. */
        @media screen and (prefers-color-scheme: dark) {
          ::highlight(peep-find) { background-color: rgb(255 214 0 / 0.3) !important; }
          ::highlight(peep-find-current) { background-color: #ffb454 !important; color: #0d1117 !important; }
          .remote-image { color: #9198a1; background: #151b23; border-color: #3d444d; }
        }
        /* Print (#26, #38): light, no page background, full width, nothing clipped, no hover-only
           anchor icons, link targets written out after external links. Pages break around code,
           rows, images, and alerts where they fit, and never right after a heading. */
        @media print {
          ::highlight(peep-find), ::highlight(peep-find-current) {
            background-color: transparent !important; color: inherit !important;
          }
          [data-peep-changes], [data-peep-diagram-controls] { display: none !important; }
          .peep-diagram-viewport > svg { transform: none !important; }
          :root { color-scheme: light !important; }
          :root, body { print-color-adjust: economy !important; }
          p { orphans: 3; widows: 3; }
          .markdown-body { max-width: none !important; padding: 0 !important; }
          .anchor { display: none !important; }
          [data-peep-sections] .markdown-body > :is(h1, h2, h3, h4, h5, h6)::after { content: none !important; }
          a[href^="http:"]::after, a[href^="https:"]::after {
            content: " (" attr(href) ")"; font-size: 0.8em; overflow-wrap: anywhere;
          }
          pre { overflow: visible !important; white-space: pre-wrap !important; overflow-wrap: anywhere !important; }
          pre code { white-space: pre-wrap !important; }
          code { overflow-wrap: anywhere !important; }
          table { display: table !important; width: 100% !important; overflow: visible !important; }
          thead { display: table-header-group !important; }
          th, td { overflow-wrap: anywhere !important; }
          tr, img, .remote-image { break-inside: avoid !important; }
          img { max-width: 100% !important; }
          h1, h2, h3, h4, h5, h6 { break-after: avoid !important; }
          .markdown-alert, .peep-diagram { break-inside: avoid; }
          .markdown-alert-title { break-after: avoid; }
        }
        /* GitHub's theme-specific images (`ColorModeImage`), and their remote-image placeholders:
           `#gh-dark-mode-only` shows only in dark mode, `#gh-light-mode-only` only in light mode
           and on paper (print is always light). Media queries follow appearance changes live. */
        @media not screen and (prefers-color-scheme: dark) {
          \(hidingRule(for: .dark))
        }
        @media screen and (prefers-color-scheme: dark) {
          \(hidingRule(for: .light))
        }
        """

    /// One rule per STL shade bucket (`STLDiagram.shadeClasses`): fill and stroke at that
    /// bucket's lightness, gray first for engines without relative colors.
    private static var stlShadeRules: String {
        STLDiagram.shadeClasses.enumerated().map { index, name in
            let lightness = "0.\(420 + 75 * index)"  // 0.42 to 0.945
            let gray = "oklch(\(lightness) 0 0)"
            let tinted = "oklch(from currentColor \(lightness) c h)"
            return ".\(name) { fill: \(gray); stroke: \(gray); fill: \(tinted); stroke: \(tinted); }"
        }
        .joined(separator: "\n        ")
    }

    /// Hides the images (and placeholders) meant only for the other appearance. More specific
    /// than the placeholder's protected `display`, so it wins within this layer.
    private static func hidingRule(for mode: ColorModeImage) -> String {
        "img[src$=\"#\(mode.fragment)\"], .remote-image.\(mode.fragment) { display: none !important; }"
    }
}
