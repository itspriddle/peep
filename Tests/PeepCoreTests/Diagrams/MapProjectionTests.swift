import Testing

@testable import PeepCore

@Suite("Map projection and SVG")
struct MapProjectionTests {
    static func pos(_ longitude: Double, _ latitude: Double) -> GeoPosition {
        GeoPosition(longitude: longitude, latitude: latitude)
    }

    static func isClose(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 1e-6
    }

    @Test("a wide shape fills the width inside the padding and is centered vertically")
    func fitsWidth() throws {
        let projection = try #require(MapProjection(fitting: [Self.pos(-10, -1), Self.pos(10, 1)]))
        let west = projection.project(Self.pos(-10, -1))
        let east = projection.project(Self.pos(10, 1))
        #expect(Self.isClose(west.horizontal, MapProjection.padding))
        #expect(Self.isClose(east.horizontal, MapProjection.width - MapProjection.padding))
        #expect(Self.isClose((west.vertical + east.vertical) / 2, MapProjection.height / 2))
        // North is up.
        #expect(east.vertical < west.vertical)
    }

    @Test("a tall shape fills the height and is centered horizontally")
    func fitsHeight() throws {
        let projection = try #require(MapProjection(fitting: [Self.pos(0, -40), Self.pos(1, 40)]))
        let south = projection.project(Self.pos(0, -40))
        let north = projection.project(Self.pos(1, 40))
        #expect(Self.isClose(north.vertical, MapProjection.padding))
        #expect(Self.isClose(south.vertical, MapProjection.height - MapProjection.padding))
        #expect(Self.isClose((south.horizontal + north.horizontal) / 2, MapProjection.width / 2))
    }

    @Test("Mercator keeps the aspect ratio: a degree of latitude near the equator is a degree of longitude")
    func aspect() throws {
        let projection = try #require(MapProjection(fitting: [Self.pos(0, 0), Self.pos(1, 1)]))
        let origin = projection.project(Self.pos(0, 0))
        let corner = projection.project(Self.pos(1, 1))
        let width = corner.horizontal - origin.horizontal
        #expect(abs(width - (origin.vertical - corner.vertical)) / width < 0.001)
    }

    @Test("latitudes past ±85.0511 are clamped; a single point is centered")
    func clampAndPoint() throws {
        #expect(
            MapProjection.mercator(Self.pos(0, 90))
                == MapProjection.mercator(Self.pos(0, MapProjection.maximumLatitude)))
        #expect(
            MapProjection.mercator(Self.pos(0, -90))
                == MapProjection.mercator(Self.pos(0, -MapProjection.maximumLatitude)))
        #expect(Self.isClose(MapProjection.mercator(Self.pos(0, MapProjection.maximumLatitude)).vertical, 0))
        let projection = try #require(MapProjection(fitting: [Self.pos(12.5, 41.9)]))
        let point = projection.project(Self.pos(12.5, 41.9))
        #expect(Self.isClose(point.horizontal, MapProjection.width / 2))
        #expect(Self.isClose(point.vertical, MapProjection.height / 2))
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
        path.move(to: SVGPoint(horizontal: 1, vertical: 1))
        path.line(to: SVGPoint(horizontal: 1.01, vertical: 1.02))
        path.line(to: SVGPoint(horizontal: 2, vertical: 3))
        path.close()
        #expect(path.data == "M1 1L2 3Z")
        var writer = SVGWriter()
        writer.empty(.path, [.pathData: .path(path)])
        #expect(writer.result == "<path d=\"M1 1L2 3Z\"/>")

        var bad = SVGPath()
        bad.move(to: SVGPoint(horizontal: .nan, vertical: 0))
        var badWriter = SVGWriter()
        badWriter.empty(.path, [.pathData: .path(bad)])
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
                    .polygon([[Self.pos(0, 0), Self.pos(4, 0), Self.pos(4, 4), Self.pos(0, 0)]]),
                    .lineString([Self.pos(0, 0), Self.pos(4, 4)]),
                    .point(Self.pos(2, 2)),
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
