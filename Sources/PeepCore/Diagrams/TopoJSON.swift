import Foundation

/// Decodes TopoJSON (the topojson-specification 1.0 `Topology`) into GeoJSON geometries, as
/// topojson-client's `feature` does:
///
/// - arcs are delta-encoded and quantized when the topology has a `transform` (positions are
///   running sums, then `position * scale + translate`); without one they are absolute;
/// - a geometry lists arc indices, and a negative index `i` means arc `~i` (`-i - 1`) reversed;
///   consecutive arcs share their joining point, which is kept once;
/// - `Point` and `MultiPoint` hold positions, quantized but not delta-encoded.
///
/// Every object in `objects` is drawn, in name order. Object names, properties, and ids are
/// never read. Positions are charged as drawn, so an arc used many times counts each time.
enum TopoJSON {
    /// The geometries in `source`, charging each drawn position against `coordinateLimit`.
    static func decode(_ source: String, coordinateLimit: inout Int) throws(DiagramDecodingError) -> [GeoGeometry] {
        let root = try JSONValues.object(from: source)
        guard try JSONValues.string(root["type"]) == "Topology" else {
            throw .invalid
        }
        var transform: QuantizationTransform?
        if let value = root["transform"] {
            transform = try QuantizationTransform(try JSONValues.object(value))
        }
        var topology = Topology(transform: transform, limit: coordinateLimit)
        topology.arcs = try topology.decodeArcs(root["arcs"])
        let objects = try JSONValues.object(root["objects"])
        var geometries: [GeoGeometry] = []
        for name in objects.keys.sorted() {
            if let geometry = try topology.geometry(try JSONValues.object(objects[name]), depth: 0) {
                geometries.append(geometry)
            }
        }
        coordinateLimit = topology.limit
        return geometries
    }
}

/// A topology's `transform`: quantized positions become `position * scale + translate`.
struct QuantizationTransform: Sendable {
    var scale: (Double, Double)
    var translate: (Double, Double)

    init(scale: (Double, Double), translate: (Double, Double)) {
        self.scale = scale
        self.translate = translate
    }

    init(_ object: [String: Any]) throws(DiagramDecodingError) {
        scale = try JSONValues.coordinatePair(object["scale"])
        translate = try JSONValues.coordinatePair(object["translate"])
    }

    func apply(_ quantized: (Double, Double)) -> GeoPosition {
        GeoPosition(
            longitude: quantized.0 * scale.0 + translate.0, latitude: quantized.1 * scale.1 + translate.1)
    }
}

private struct Topology {
    var transform: QuantizationTransform?
    var limit: Int
    var arcs: [[GeoPosition]] = []

    /// Each arc's absolute positions.
    func decodeArcs(_ value: Any?) throws(DiagramDecodingError) -> [[GeoPosition]] {
        var arcs: [[GeoPosition]] = []
        for arcValue in try JSONValues.array(value) {
            var arc: [GeoPosition] = []
            var sum = (0.0, 0.0)
            for pointValue in try JSONValues.array(arcValue) {
                let point = try JSONValues.coordinatePair(pointValue)
                if let transform {
                    sum.0 += point.0
                    sum.1 += point.1
                    arc.append(transform.apply(sum))
                } else {
                    arc.append(GeoPosition(longitude: point.0, latitude: point.1))
                }
            }
            arcs.append(arc)
        }
        return arcs
    }

    /// The geometry `object` describes, or `nil` for a null geometry (`"type": null`).
    mutating func geometry(_ object: [String: Any], depth: Int) throws(DiagramDecodingError) -> GeoGeometry? {
        guard let typeValue = object["type"], !(typeValue is NSNull) else {
            return nil
        }
        let type = try JSONValues.string(typeValue)
        switch type {
        case "GeometryCollection":
            guard depth < GeoJSON.maximumNesting else {
                throw .invalid
            }
            var geometries: [GeoGeometry] = []
            for member in try JSONValues.array(object["geometries"]) {
                if let geometry = try geometry(try JSONValues.object(member), depth: depth + 1) {
                    geometries.append(geometry)
                }
            }
            return .collection(geometries)
        case "Point":
            return .point(try point(object["coordinates"]))
        case "MultiPoint":
            var points: [GeoPosition] = []
            for value in try JSONValues.array(object["coordinates"]) {
                points.append(try point(value))
            }
            return .multiPoint(points)
        case "LineString":
            return .lineString(try line(object["arcs"]))
        case "MultiLineString":
            return .multiLineString(try lines(object["arcs"]))
        case "Polygon":
            return .polygon(try lines(object["arcs"]))
        case "MultiPolygon":
            var polygons: [[[GeoPosition]]] = []
            for polygon in try JSONValues.array(object["arcs"]) {
                polygons.append(try lines(polygon))
            }
            return .multiPolygon(polygons)
        default:
            throw .invalid
        }
    }

    private mutating func point(_ value: Any?) throws(DiagramDecodingError) -> GeoPosition {
        try charge(1)
        let pair = try JSONValues.coordinatePair(value)
        return transform?.apply(pair) ?? GeoPosition(longitude: pair.0, latitude: pair.1)
    }

    private mutating func lines(_ value: Any?) throws(DiagramDecodingError) -> [[GeoPosition]] {
        var lines: [[GeoPosition]] = []
        for indices in try JSONValues.array(value) {
            lines.append(try line(indices))
        }
        return lines
    }

    /// The arcs `value` lists, joined: each arc after the first starts where the last ended, so
    /// that shared point is kept once.
    private mutating func line(_ value: Any?) throws(DiagramDecodingError) -> [GeoPosition] {
        var positions: [GeoPosition] = []
        for indexValue in try JSONValues.array(value) {
            let index = try arcIndex(indexValue)
            let arc = index >= 0 ? arcs[index] : Array(arcs[~index].reversed())
            if !positions.isEmpty {
                positions.removeLast()
            }
            try charge(arc.count)
            positions.append(contentsOf: arc)
        }
        return positions
    }

    /// An arc index: an integer naming an arc, either way round.
    private func arcIndex(_ value: Any?) throws(DiagramDecodingError) -> Int {
        let number = try JSONValues.number(value)
        guard number.rounded() == number, abs(number) <= Double(arcs.count) else {
            throw .invalid
        }
        let index = Int(number)
        guard index >= 0 ? index < arcs.count : ~index < arcs.count else {
            throw .invalid
        }
        return index
    }

    private mutating func charge(_ count: Int) throws(DiagramDecodingError) {
        guard count <= limit else {
            throw .overLimit
        }
        limit -= count
    }
}
