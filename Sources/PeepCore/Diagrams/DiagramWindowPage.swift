/// The page the app's diagram window shows (Open in Window on a diagram's controls): one
/// diagram's SVG, fitted to the window, over the document's theme.
///
/// The SVG is the viewer's own markup read back from its page: the renderer's map or STL SVG
/// (escaped by construction, `SVGWriter`) or mermaid's output (`securityLevel: "strict"`, then
/// scrubbed by `MermaidDiagrams.js`). The page carries `ContentSecurityPolicy.diagramWindow` (no
/// scripts, no loads but `data:` images) and is shown in a web view with JavaScript off, no user
/// scripts, and no message handlers, so nothing in it can run or reach the app.
///
/// The theme's layers (`ThemeBase`, then the theme) give it the document's text color, which
/// maps and models are drawn in, and its background. An unlayered rule after them, which beats
/// every layer, turns the article into a full-window frame and lets the SVG fill it (its
/// `viewBox` keeps the aspect ratio); `!important` overrides mermaid's inline `max-width`.
public struct DiagramWindowPage: Sendable {
    public var title: String
    public var svg: String
    public var theme: Theme

    public init(title: String, svg: String, theme: Theme) {
        self.title = title
        self.svg = svg
        self.theme = theme
    }

    /// The window's layout, unlayered so it beats the theme.
    static let layoutCSS = """
        html, body { height: 100%; margin: 0; overflow: hidden; }
        article.markdown-body {
          box-sizing: border-box; display: flex; align-items: center; justify-content: center;
          width: 100%; max-width: none; height: 100%; margin: 0; padding: 24px;
        }
        article.markdown-body > svg {
          display: block; width: 100%; height: 100%; max-width: none !important; max-height: none !important;
        }
        """

    public var html: String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(ContentSecurityPolicy.diagramWindow.header)">
        <meta name="color-scheme" content="light dark">
        <title>\(HTMLDocument.escape(title))</title>
        <style id="\(ThemeLayer.base.name)">
        \(ThemeBase.layerCSS)
        </style>
        <style id="\(ThemeLayer.theme.name)">
        \(theme.layerCSS)
        </style>
        <style id="peep-diagram-window">
        \(Self.layoutCSS)
        </style>
        </head>
        <body>
        <article class="markdown-body">
        \(svg)
        </article>
        </body>
        </html>
        """
    }
}
