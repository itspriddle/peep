import Foundation
import Testing

@testable import PeepCore

@Suite("Diagram rendering")
struct DiagramRenderingTests {
    static let point = #"{"type":"Point","coordinates":[12.5,41.9]}"#
    static let topology =
        #"{"type":"Topology","objects":{"a":{"type":"LineString","arcs":[0]}},"arcs":[[[0,0],[1,1]]]}"#

    static func render(_ markdown: String, configure: (inout RenderOptions) -> Void = { _ in }) -> RenderedDocument {
        var options = RenderOptions()
        options.headingAnchors = false
        configure(&options)
        return HTMLRenderer(options: options).render(markdown)
    }

    static func fence(_ language: String, _ code: String) -> String {
        "```\(language)\n\(code)\n```\n"
    }

    @Test("geojson and topojson blocks become figures, whatever the language's case")
    func figures() {
        let geojson = Self.render(Self.fence("GeoJSON", Self.point)).html
        #expect(geojson.hasPrefix(#"<figure class="peep-diagram peep-diagram-geojson"><svg class="peep-map""#))
        #expect(geojson.hasSuffix("</svg><figcaption class=\"sr-only\">GeoJSON map</figcaption></figure>\n"))
        #expect(!geojson.contains("<pre"))
        let topojson = Self.render(Self.fence("topojson extra words", Self.topology)).html
        #expect(topojson.hasPrefix(#"<figure class="peep-diagram peep-diagram-topojson">"#))
        #expect(topojson.contains(#"aria-label="TopoJSON map""#))
        #expect(topojson.contains("<figcaption class=\"sr-only\">TopoJSON map</figcaption>"))
    }

    @Test(
        "unreadable or empty blocks stay code blocks",
        arguments: [
            "not json",
            #"{"type":"Point","coordinates":[1]}"#,
            #"{"type":"FeatureCollection","features":[]}"#,
            #"{"type":"Feature","geometry":null}"#,
            "",
        ])
    func malformed(json: String) {
        let html = Self.render(Self.fence("geojson", json)).html
        #expect(html.hasPrefix("<pre><code class=\"language-geojson\">"))
        #expect(!html.contains("<svg"))
    }

    @Test("other languages, indented code, and diagrams off stay code blocks")
    func notDiagrams() {
        #expect(Self.render(Self.fence("json", Self.point)).html.hasPrefix("<pre>"))
        #expect(Self.render("    " + Self.point + "\n").html.hasPrefix("<pre>"))
        let off = Self.render(Self.fence("geojson", Self.point)) { $0.diagrams = false }
        #expect(off.html.hasPrefix("<pre><code class=\"language-geojson\">"))
        #expect(!RenderOptions.spec.diagrams)
        #expect(HTMLRenderer(options: .spec).render(Self.fence("geojson", Self.point)).html.hasPrefix("<pre>"))
    }

    @Test("diagrams nested in containers are drawn, and carry the block's source line")
    func nestedAndSourceLines() {
        let markdown = "intro\n\n> - item\n>\n>   ```geojson\n>   \(Self.point)\n>   ```\n"
        let html = Self.render(markdown) { $0.sourceLines = true }.html
        #expect(html.contains(#"<figure class="peep-diagram peep-diagram-geojson" data-source-line="5"><svg"#))
    }

    @Test("names and properties containing markup never reach the output")
    func noInputInMarkup() {
        let geojson = """
            {"type":"FeatureCollection","name":"<script>alert(1)</script>","features":[
             {"type":"Feature","id":"<img src=x onerror=alert(1)>",
              "properties":{"name":"<script>alert(2)</script>","<script>":"\\"><svg onload=alert(3)>"},
              "geometry":{"type":"Point","coordinates":[1,2]}}]}
            """
        let topojson = """
            {"type":"Topology","objects":{"<script>alert(4)</script>":{"type":"Point","coordinates":[1,2],
             "properties":{"title":"</svg><script>alert(5)</script>"}}},"arcs":[]}
            """
        for (language, json) in [("geojson", geojson), ("topojson", topojson)] {
            let html = Self.render(Self.fence(language, json)).html
            #expect(html.contains("<svg"))
            #expect(!html.contains("<script"))
            #expect(!html.contains("alert"))
            #expect(!html.contains("onerror"))
            #expect(!html.contains("onload"))
        }
    }

    @Test("a diagram block isn't highlighted, and has no words")
    func noHighlightNoWords() {
        let document = Self.render("one two\n\n" + Self.fence("geojson", Self.point))
        #expect(!document.html.contains("hljs"))
        #expect(document.wordCount == 2)
        let code = Self.render("one two\n\n" + Self.fence("geojson", Self.point)) { $0.diagrams = false }
        #expect(code.wordCount > 2)
    }

    @Test("a block over the size cap stays code")
    func blockCap() {
        let padding = String(repeating: " ", count: DiagramRendering.maximumBlockBytes)
        let html = Self.render(Self.fence("geojson", Self.point + padding)).html
        #expect(html.hasPrefix("<pre>"))
    }

    @Test("the document's coordinate budget: a block that doesn't fit is code, a later smaller one is drawn")
    func documentBudget() {
        func line(_ count: Int) -> CodeBlock {
            let coordinates = (0..<count).map { "[\($0),\($0 % 7)]" }.joined(separator: ",")
            return CodeBlock(
                info: "geojson", literal: #"{"type":"LineString","coordinates":[\#(coordinates)]}"#, isFenced: true)
        }
        var rendering = DiagramRendering(coordinateBudget: 10)
        #expect(rendering.diagram(for: line(6)) != nil)
        #expect(rendering.remainingCoordinates == 4)
        #expect(rendering.diagram(for: line(5)) == nil)
        #expect(rendering.remainingCoordinates == 4)
        #expect(rendering.diagram(for: line(4)) != nil)
        #expect(rendering.remainingCoordinates == 0)
        #expect(DiagramRendering.documentCoordinateBudget == 200_000)
    }

    @Test("a document over the coordinate budget draws the blocks that fit")
    func documentBudgetEndToEnd() {
        let count = DiagramRendering.documentCoordinateBudget / 2 + 1
        let coordinates = (0..<count).map { "[\($0 % 360 - 180),\($0 % 80)]" }.joined(separator: ",")
        let block = Self.fence("geojson", #"{"type":"MultiPoint","coordinates":[\#(coordinates)]}"#)
        let html = Self.render(block + "\n" + block + "\n" + Self.fence("geojson", Self.point)).html
        #expect(html.components(separatedBy: "<figure").count == 3)
        #expect(html.components(separatedBy: "<pre>").count == 2)
    }
}
