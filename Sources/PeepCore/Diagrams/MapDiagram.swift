/// Draws map geometries (`GeoJSON`, `TopoJSON`) as an SVG: shapes only, no tiles (VISION: no
/// remote content).
///
/// ```html
/// <svg class="peep-map" viewBox="0 0 800 400" role="img" aria-label="GeoJSON map">
///   <path class="peep-map-area" fill-rule="evenodd" d="…"/>  <!-- one per polygon -->
///   <path class="peep-map-line" d="…"/>                       <!-- every line -->
///   <path class="peep-map-point" d="…"/>                      <!-- every point -->
/// </svg>
/// ```
///
/// Paths carry classes, never colors: `ThemeBase` styles them from `currentColor`, so every
/// theme works in light, dark, and print. Polygons use the even-odd rule, so holes are holes
/// whichever way their rings wind.
enum MapDiagram {
    /// A point's radius, in viewBox units.
    static let pointRadius = 5.0

    /// The SVG for `geometries`, or `nil` when they hold no positions (or a number won't fit).
    static func svg(for geometries: [GeoGeometry], label: String) -> String? {
        var shapes = MapShapes()
        for geometry in geometries {
            shapes.add(geometry)
        }
        guard let projection = MapProjection(fitting: shapes.allPositions) else {
            return nil
        }
        var writer = SVGWriter()
        writer.start(
            .svg,
            [
                .class: .keyword("peep-map"),
                .viewBox: .numbers([0, 0, MapProjection.width, MapProjection.height]),
                .role: .keyword("img"),
                .ariaLabel: .text(label),
            ])
        for polygon in shapes.areas {
            var path = SVGPath()
            for ring in polygon where !ring.isEmpty {
                trace(ring, with: projection, into: &path)
                path.close()
            }
            if !path.isEmpty {
                writer.empty(
                    .path, [.class: .keyword("peep-map-area"), .fillRule: .keyword("evenodd"), .pathData: .path(path)])
            }
        }
        var lines = SVGPath()
        for line in shapes.lines {
            trace(line, with: projection, into: &lines)
        }
        if !lines.isEmpty {
            writer.empty(.path, [.class: .keyword("peep-map-line"), .pathData: .path(lines)])
        }
        var points = SVGPath()
        for point in shapes.points {
            points.dot(at: projection.project(point), radius: pointRadius)
        }
        if !points.isEmpty {
            writer.empty(.path, [.class: .keyword("peep-map-point"), .pathData: .path(points)])
        }
        writer.end()
        return writer.result
    }

    private static func trace(_ positions: [GeoPosition], with projection: MapProjection, into path: inout SVGPath) {
        for (index, position) in positions.enumerated() {
            if index == 0 {
                path.move(to: projection.project(position))
            } else {
                path.line(to: projection.project(position))
            }
        }
    }
}

/// Geometries sorted by how they're drawn: filled areas, stroked lines, and dots.
struct MapShapes: Sendable, Equatable {
    var areas: [[[GeoPosition]]] = []
    var lines: [[GeoPosition]] = []
    var points: [GeoPosition] = []

    /// Adds `geometry`'s parts. Collections are flattened with an explicit stack.
    mutating func add(_ geometry: GeoGeometry) {
        var stack = [geometry]
        while let geometry = stack.popLast() {
            switch geometry {
            case .point(let point): points.append(point)
            case .multiPoint(let multiPoint): points += multiPoint
            case .lineString(let line): lines.append(line)
            case .multiLineString(let multiLine): lines += multiLine
            case .polygon(let polygon): areas.append(polygon)
            case .multiPolygon(let multiPolygon): areas += multiPolygon
            case .collection(let geometries): stack += geometries.reversed()
            }
        }
    }

    var allPositions: [GeoPosition] {
        areas.flatMap { $0.flatMap(\.self) } + lines.flatMap(\.self) + points
    }
}
