// Diagram markup for `HTMLRenderer` (M7): a code block `DiagramRendering` drew.

extension HTMLRenderer {
    /// Writes a drawn code block in place of its `<pre>`:
    ///
    /// ```html
    /// <figure class="peep-diagram peep-diagram-geojson" data-source-line="N"><svg …>…</svg>
    /// <figcaption class="sr-only">GeoJSON map</figcaption></figure>
    /// ```
    ///
    /// `svg` is `SVGWriter` output (trusted by construction); the caption is the kind's fixed
    /// label.
    func renderDiagram(_ svg: String, kind: DiagramKind, _ node: MarkdownNode, into output: inout HTMLOutput) {
        output.newlineIfNeeded()
        output.raw("<figure class=\"peep-diagram ")
        output.text(kind.figureClass)
        output.raw("\"")
        writeSourceLine(of: node, into: &output)
        output.raw(">")
        output.raw(svg)
        output.raw("<figcaption class=\"sr-only\">")
        output.text(kind.label)
        output.raw("</figcaption></figure>\n")
    }
}
