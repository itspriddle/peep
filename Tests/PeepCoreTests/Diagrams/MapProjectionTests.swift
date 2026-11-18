import Testing

@testable import PeepCore

@Suite("Map projection and SVG")
struct MapProjectionTests {
    static func p(_ longitude: Double, _ latitude: Double) -> GeoPosition {
        GeoPosition(longitude: longitude, latitude: latitude)
    }

    static func isClose(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 1e-6
    }

    @Test("a wide shape fills the width inside the padding and is centered vertically")
    func fitsWidth() throws {
        let projection = try #require(MapProjection(fitting: [Self.p(-10, -1), Self.p(10, 1)]))
        let west = projection.project(Self.p(-10, -1))
        let east = projection.project(Self.p(10, 1))
        #expect(Self.isClose(west.x, MapProjection.padding))
        #expect(Self.isClose(east.x, MapProjection.width - MapProjection.padding))
        #expect(Self.isClose((west.y + east.y) / 2, MapProjection.height / 2))
        // North is up.
        #expect(east.y < west.y)
    }

    @Test("a tall shape fills the height and is centered horizontally")
    func fitsHeight() throws {
        let projection = try #require(MapProjection(fitting: [Self.p(0, -40), Self.p(1, 40)]))
        let south = projection.project(Self.p(0, -40))
        let north = projection.project(Self.p(1, 40))
        #expect(Self.isClose(north.y, MapProjection.padding))
        #expect(Self.isClose(south.y, MapProjection.height - MapProjection.padding))
        #expect(Self.isClose((south.x + north.x) / 2, MapProjection.width / 2))
    }

    @Test("Mercator keeps the aspect ratio: a degree of latitude near the equator is a degree of longitude")
    func aspect() throws {
        let projection = try #require(MapProjection(fitting: [Self.p(0, 0), Self.p(1, 1)]))
        let a = projection.project(Self.p(0, 0))
        let b = projection.project(Self.p(1, 1))
        #expect(abs((b.x - a.x) - (a.y - b.y)) / (b.x - a.x) < 0.001)
    }

    @Test("latitudes past ±85.0511 are clamped; a single point is centered")
    func clampAndPoint() throws {
        #expect(MapProjection.mercator(Self.p(0, 90)) == MapProjection.mercator(Self.p(0, MapProjection.maximumLatitude)))
        #expect(MapProjection.mercator(Self.p(0, -90)) == MapProjection.mercator(Self.p(0, -MapProjection.maximumLatitude)))
        #expect(Self.isClose(MapProjection.mercator(Self.p(0, MapProjection.maximumLatitude)).y, 0))
        let projection = try #require(MapProjection(fitting: [Self.p(12.5, 41.9)]))
        let point = projection.project(Self.p(12.5, 41.9))
        #expect(Self.isClose(point.x, MapProjection.width / 2))
        #expect(Self.isClose(point.y, MapProjection.height / 2))
        #expect(MapProjection(fitting: [GeoPosition]()) == nil)
    }

    @Test("numbers are rounded to a tenth, without exponents or trailing zeros; non-finite is refused")
    func numbers() {
        #expect(SVGNumber.format(0) == "0")
        #expect(SVGNumber.format(-0.04) == "0")
        #expect(SVGNumber.format(12.34) == "12.3")
        #expect(SVGNumber.format(-12.36) == "-12.4")
        #expect(SVGNumber.format(400) == "400")
        #expect(SVGNumber.format(1e-20) == "0")
        #expect(SVGNumber.format(.nan) == nil)
        #expect(SVGNumber.format(.infinity) == nil)
        #expect(SVGNumber.format(1e12) == nil)
    }

    @Test("paths drop points that round to the one before; a non-finite point voids the SVG")
    func paths() {
        var path = SVGPath()
        path.move(x: 1, y: 1)
        path.line(x: 1.01, y: 1.02)
        path.line(x: 2, y: 3)
        path.close()
        #expect(path.data == "M1 1L2 3Z")
        var writer = SVGWriter()
        writer.empty(.path, [.d: .path(path)])
        #expect(writer.result == "<path d=\"M1 1L2 3Z\"/>")

        var bad = SVGPath()
        bad.move(x: .nan, y: 0)
        var badWriter = SVGWriter()
        badWriter.empty(.path, [.d: .path(bad)])
        #expect(badWriter.result == nil)
        var badNumbers = SVGWriter()
        badNumbers.empty(.svg, [.viewBox: .numbers([0, .infinity])])
        #expect(badNumbers.result == nil)
    }

    @Test("text values are escaped, and an unclosed element voids the SVG")
    func writerText() {
        var writer = SVGWriter()
        writer.start(.svg, [.ariaLabel: .text("<script>\"&")])
        #expect(writer.result == nil)
        writer.end()
        #expect(writer.result == "<svg aria-label=\"&lt;script&gt;&quot;&amp;\"></svg>")
    }

    @Test("a map draws areas, lines, and points with classes and no colors")
    func mapSVG() throws {
        let svg = try #require(
            MapDiagram.svg(
                for: [
                    .polygon([[Self.p(0, 0), Self.p(4, 0), Self.p(4, 4), Self.p(0, 0)]]),
                    .lineString([Self.p(0, 0), Self.p(4, 4)]),
                    .point(Self.p(2, 2)),
                ],
                label: "GeoJSON map"))
        #expect(svg.hasPrefix(#"<svg class="peep-map" viewBox="0 0 800 400" role="img" aria-label="GeoJSON map">"#))
        #expect(svg.contains(#"<path class="peep-map-area" fill-rule="evenodd" d="M"#))
        #expect(svg.contains(#"<path class="peep-map-line" d="M"#))
        #expect(svg.contains(#"<path class="peep-map-point" d="M"#))
        #expect(!svg.contains("fill=") && !svg.contains("stroke") && !svg.contains("style"))
        #expect(svg.hasSuffix("</svg>"))
    }

    @Test("nothing to draw is no map")
    func empty() {
        #expect(MapDiagram.svg(for: [], label: "x") == nil)
        #expect(MapDiagram.svg(for: [.collection([]), .lineString([]), .polygon([[]])], label: "x") == nil)
    }
}
