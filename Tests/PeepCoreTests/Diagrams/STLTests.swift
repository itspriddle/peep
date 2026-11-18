import Foundation
import Testing

@testable import PeepCore

@Suite("STL models")
struct STLTests {
    /// A unit cube's corners, and its twelve facets counterclockwise from outside.
    static let corners = [
        [0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0], [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1],
    ]
    static let cubeFacets = [
        [0, 3, 2], [0, 2, 1],  // bottom
        [4, 5, 6], [4, 6, 7],  // top
        [0, 1, 5], [0, 5, 4],  // front (-north)
        [1, 2, 6], [1, 6, 5],  // right (+east)
        [2, 3, 7], [2, 7, 6],  // back
        [3, 0, 4], [3, 4, 7],  // left
    ]

    /// A facet over `vertices`, each three numbers.
    static func facet(_ vertices: [[Double]], normal: String = "0 0 0") -> String {
        let lines = vertices.map { "      vertex " + $0.map { "\($0)" }.joined(separator: " ") }
        return (["  facet normal \(normal)", "    outer loop"] + lines + ["    endloop", "  endfacet"])
            .joined(separator: "\n")
    }

    static func solid(_ facets: [String], name: String = "model") -> String {
        (["solid \(name)"] + facets + ["endsolid \(name)"]).joined(separator: "\n") + "\n"
    }

    static func cube(name: String = "cube") -> String {
        solid(
            cubeFacets.map { indices in
                facet(indices.map { corners[$0].map(Double.init) })
            }, name: name)
    }

    static func decode(_ source: String, limit: Int = STL.maximumTriangles) -> [STLTriangle]? {
        try? STL.decode(source, triangleLimit: limit)
    }

    static func render(_ markdown: String) -> String {
        var options = RenderOptions()
        options.headingAnchors = false
        return HTMLRenderer(options: options).render(markdown).html
    }

    static func fence(_ code: String, language: String = "stl") -> String {
        "```\(language)\n\(code)```\n"
    }

    // MARK: Parsing

    @Test("a cube decodes to twelve facets, with the file's normals ignored")
    func cube() throws {
        let triangles = try #require(Self.decode(Self.cube()))
        #expect(triangles.count == 12)
        #expect(triangles[2].first == STLVector(east: 0, north: 0, upward: 1))
        #expect(triangles[2].normal == STLVector(east: 0, north: 0, upward: 1))
        #expect(triangles[0].normal == STLVector(east: 0, north: 0, upward: -1))
    }

    @Test("keywords in any case, tabs, CRLF, blank lines, odd normals, and several solids")
    func tolerant() throws {
        let messy = """
            SOLID Exported by Some CAD 2024\r
            \r
            \tFacet Normal NaN nan -0\r
            \t\tOUTER   LOOP\r
            \t\t\tVERTEX 0 0 0\r
            \t\t\tvertex 1.0e0 0 0   \r
            \t\t\tVertex 0 +1 0\r
            \t\tENDLOOP\r
            \tENDFACET\r
            ENDSOLID\r
            solid second
            facet
            outer loop
            vertex 0 0 1
            vertex 1 0 1
            vertex 0 1 1
            endloop
            endfacet
            endsolid second
            """
        let triangles = try #require(Self.decode(messy))
        #expect(triangles.count == 2)
        #expect(triangles[0].third == STLVector(east: 0, north: 1, upward: 0))
    }

    /// One valid facet with `text` replaced by `replacement`.
    static func broken(_ text: String, _ replacement: String) -> String {
        solid([facet([[0, 0, 0], [1, 0, 0], [0, 1, 0]]).replacingOccurrences(of: text, with: replacement)])
    }

    static let malformedSources = [
        "",
        "solid empty\nendsolid empty\n",
        "facet normal 0 0 1\n",
        "solid x\n" + facet([[0, 0, 0], [1, 0, 0], [0, 1, 0]]) + "\n",
        "solid x\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nendloop\nendfacet\nendsolid x\n",
        "solid x\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nvertex 0 1 0\nvertex 1 1 0\n"
            + "endloop\nendfacet\nendsolid x\n",
        broken("vertex 0.0 1.0 0.0", "vertex 0 one 0"),
        broken("vertex 0.0 1.0 0.0", "vertex 0 1"),
        broken("vertex 0.0 1.0 0.0", "vertex 0 1 0 0"),
        broken("vertex 0.0 1.0 0.0", "vertex 0 inf 0"),
        broken("vertex 0.0 1.0 0.0", "vertex 0 nan 0"),
        broken("vertex 0.0 1.0 0.0", "vertex 0 1e999 0"),
        broken("outer loop", "outer"),
        broken("endloop", "endloop now"),
        broken("endfacet", "endfacet extra"),
        solid([facet([[0, 0, 0], [1, 0, 0], [0, 1, 0]])]) + "garbage\n",
        #"{"type":"Point","coordinates":[1,2]}"#,
    ]

    @Test("malformed input is invalid", arguments: STLTests.malformedSources)
    func malformed(source: String) {
        #expect(throws: DiagramDecodingError.invalid) { try STL.decode(source, triangleLimit: 100) }
    }

    @Test("more facets than the limit is over the limit")
    func triangleLimit() {
        #expect(STL.maximumTriangles == 50_000)
        #expect(Self.decode(Self.cube(), limit: 12)?.count == 12)
        #expect(throws: DiagramDecodingError.overLimit) { try STL.decode(Self.cube(), triangleLimit: 11) }
    }

    // MARK: Projection

    @Test("a cube shows its top, front, and right sides, in three shades, top lightest")
    func cubeFaces() throws {
        let triangles = try #require(Self.decode(Self.cube()))
        let projection = try #require(STLProjection(fitting: triangles))
        let faces = projection.faces(of: triangles)
        #expect(faces.count == 6)
        let lit = STLProjection.shade(of: STLVector(east: 0, north: 0, upward: 1))
        let front = STLProjection.shade(of: STLVector(east: 0, north: -1, upward: 0))
        let right = STLProjection.shade(of: STLVector(east: 1, north: 0, upward: 0))
        #expect(lit == STLProjection.shadeCount - 1)
        #expect(lit > front && front > right)
        #expect(faces.map(\.shade).sorted() == [right, right, front, front, lit, lit])
        // Fitted: the cube's silhouette touches the padding top and bottom, centered across.
        let points = faces.flatMap(\.corners)
        let top = try #require(points.map(\.vertical).min())
        let bottom = try #require(points.map(\.vertical).max())
        let left = try #require(points.map(\.horizontal).min())
        let rightEdge = try #require(points.map(\.horizontal).max())
        #expect(abs(top - STLProjection.padding) < 1e-9)
        #expect(abs(bottom - (STLProjection.height - STLProjection.padding)) < 1e-9)
        #expect(abs((left + rightEdge) / 2 - STLProjection.width / 2) < 1e-9)
    }

    @Test("back faces and degenerate facets are culled; a model facing away draws nothing")
    func culling() throws {
        let facingUp = STLTriangle(
            first: STLVector(east: 0, north: 0, upward: 0), second: STLVector(east: 1, north: 0, upward: 0),
            third: STLVector(east: 0, north: 1, upward: 0))
        let down = STLTriangle(first: facingUp.first, second: facingUp.third, third: facingUp.second)
        let line = STLTriangle(
            first: facingUp.first, second: facingUp.second, third: STLVector(east: 2, north: 0, upward: 0))
        let projection = try #require(STLProjection(fitting: [facingUp, down, line]))
        #expect(projection.faces(of: [facingUp, down, line]).count == 1)
        #expect(STLDiagram.svg(for: [down], label: "STL model") == nil)
        #expect(STLDiagram.svg(for: [line], label: "STL model") == nil)
        #expect(
            STLProjection(fitting: [STLTriangle(first: facingUp.first, second: facingUp.first, third: facingUp.first)])
                == nil)
    }

    @Test("facets are drawn back to front")
    func paintersOrder() throws {
        // Two parallel squares facing the camera's side; the nearer one is listed first.
        let near = STLTriangle(
            first: STLVector(east: 5, north: 0, upward: 0), second: STLVector(east: 5, north: 1, upward: 0),
            third: STLVector(east: 5, north: 0, upward: 1))
        let far = STLTriangle(
            first: STLVector(east: 0, north: 0, upward: 0), second: STLVector(east: 0, north: 1, upward: 0),
            third: STLVector(east: 0, north: 0, upward: 1))
        let projection = try #require(STLProjection(fitting: [near, far]))
        let faces = projection.faces(of: [near, far])
        #expect(faces.compactMap(\.corners.first) == [projection.project(far.first), projection.project(near.first)])
    }

    @Test("the cube's SVG: classes per shade, no colors, nothing from the input")
    func cubeSVG() throws {
        let triangles = try #require(Self.decode(Self.cube()))
        let svg = try #require(STLDiagram.svg(for: triangles, label: "STL model"))
        #expect(svg.hasPrefix(#"<svg class="peep-stl" viewBox="0 0 800 400" role="img" aria-label="STL model">"#))
        #expect(svg.hasSuffix("</svg>"))
        #expect(svg.contains(#"<path class="peep-stl-s7" d="M"#))
        #expect(!svg.contains("fill") && !svg.contains("stroke") && !svg.contains("style"))
        let shades = Set(STLDiagram.shadeClasses.map(\.description).filter { svg.contains("\"\($0)\"") })
        #expect(shades.count == 3)
        #expect(STLDiagram.shadeClasses.count == STLProjection.shadeCount)
    }

    // MARK: Rendering

    @Test("an stl block becomes a figure, whatever the language's case")
    func figure() {
        let html = Self.render(Self.fence(Self.cube(), language: "STL"))
        #expect(html.hasPrefix(#"<figure class="peep-diagram peep-diagram-stl"><svg class="peep-stl""#))
        #expect(html.hasSuffix("</svg><figcaption class=\"sr-only\">STL model</figcaption></figure>\n"))
        #expect(!html.contains("<pre"))
    }

    @Test("malformed or invisible models stay code blocks")
    func codeBlocks() {
        let down = Self.solid([Self.facet([[0, 0, 0], [0, 1, 0], [1, 0, 0]])])
        for source in ["solid x\nendsolid x\n", "not stl\n", down] {
            let html = Self.render(Self.fence(source))
            #expect(html.hasPrefix("<pre><code class=\"language-stl\">"))
            #expect(!html.contains("<svg"))
        }
    }

    @Test("a hostile solid name never reaches the output unescaped")
    func hostileName() {
        let names = [
            "<script>alert(1)</script>", #""><svg onload=alert(2)>"#, "</svg><img src=x onerror=alert(3)>",
        ]
        for name in names {
            let html = Self.render(Self.fence(Self.cube(name: name)))
            #expect(html.contains("<svg class=\"peep-stl\""))
            #expect(!html.contains("<script"))
            #expect(!html.contains("alert"))
            #expect(!html.contains("onload"))
            #expect(!html.contains("onerror"))
        }
        // As code (diagrams off) the name is escaped like any code.
        var options = RenderOptions()
        options.diagrams = false
        let code = HTMLRenderer(options: options).render(Self.fence(Self.cube(name: names[0]))).html
        #expect(code.contains("solid &lt;script&gt;"))
        #expect(!code.contains("<script"))
    }

    @Test("facets count three coordinates each against the document's budget")
    func budget() {
        let block = CodeBlock(info: "stl", literal: Self.cube(), isFenced: true)
        var rendering = DiagramRendering(coordinateBudget: 40)
        #expect(rendering.diagram(for: block) != nil)
        #expect(rendering.remainingCoordinates == 4)
        #expect(rendering.diagram(for: block) == nil)
        #expect(rendering.remainingCoordinates == 4)
    }
}
