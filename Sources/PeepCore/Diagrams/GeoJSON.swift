import Foundation

/// A longitude and latitude in degrees (a GeoJSON position; altitude and anything after it are
/// dropped).
struct GeoPosition: Sendable, Equatable {
    var longitude: Double
    var latitude: Double
}

/// A GeoJSON geometry (RFC 7946 section 3.1), the model `GeoJSON` and `TopoJSON` decode into and
/// `MapDiagram` draws.
indirect enum GeoGeometry: Sendable, Equatable {
    case point(GeoPosition)
    case multiPoint([GeoPosition])
    case lineString([GeoPosition])
    case multiLineString([[GeoPosition]])
    /// Rings: the exterior first, then holes.
    case polygon([[GeoPosition]])
    case multiPolygon([[[GeoPosition]]])
    case collection([GeoGeometry])

    /// How many positions the geometry holds.
    var positionCount: Int {
        switch self {
        case .point: 1
        case .multiPoint(let points), .lineString(let points): points.count
        case .multiLineString(let lines), .polygon(let lines): lines.reduce(0) { $0 + $1.count }
        case .multiPolygon(let polygons): polygons.reduce(0) { $0 + $1.reduce(0) { $0 + $1.count } }
        case .collection(let geometries): geometries.reduce(0) { $0 + $1.positionCount }
        }
    }
}

/// Why a diagram's source couldn't be read. Either way the block renders as code.
enum DiagramDecodingError: Error, Equatable {
    /// Not JSON, or not the structure the format requires.
    case invalid
    /// More coordinates than the caller allowed.
    case overLimit
}

/// Decodes GeoJSON (RFC 7946): a geometry of any type, a `Feature`, or a `FeatureCollection`,
/// into the geometries to draw. Features without a geometry (`null`) are skipped; properties,
/// ids, and foreign members are never read. Anything malformed fails the whole block, so a
/// diagram is all or nothing.
enum GeoJSON {
    /// The deepest `GeometryCollection` nesting read.
    static let maximumNesting = 32

    /// The geometries in `source`, charging each position against `coordinateLimit`.
    static func decode(_ source: String, coordinateLimit: inout Int) throws(DiagramDecodingError) -> [GeoGeometry] {
        let root = try JSONValues.object(from: source)
        var reader = PositionReader(limit: coordinateLimit)
        let geometries = try reader.geometries(inRoot: root)
        coordinateLimit = reader.limit
        return geometries
    }
}

/// Reads GeoJSON objects out of `JSONSerialization` values, counting positions.
private struct PositionReader {
    var limit: Int

    mutating func geometries(inRoot root: [String: Any]) throws(DiagramDecodingError) -> [GeoGeometry] {
        switch try JSONValues.string(root["type"]) {
        case "FeatureCollection":
            let features = try JSONValues.array(root["features"])
            var geometries: [GeoGeometry] = []
            for feature in features {
                if let geometry = try self.feature(try JSONValues.object(feature)) {
                    geometries.append(geometry)
                }
            }
            return geometries
        case "Feature":
            return try feature(root).map { [$0] } ?? []
        default:
            return [try geometry(root, depth: 0)]
        }
    }

    private mutating func feature(_ object: [String: Any]) throws(DiagramDecodingError) -> GeoGeometry? {
        guard try JSONValues.string(object["type"]) == "Feature" else {
            throw .invalid
        }
        guard let value = object["geometry"], !(value is NSNull) else {
            return nil
        }
        return try geometry(try JSONValues.object(value), depth: 0)
    }

    private mutating func geometry(_ object: [String: Any], depth: Int) throws(DiagramDecodingError) -> GeoGeometry {
        let type = try JSONValues.string(object["type"])
        if type == "GeometryCollection" {
            guard depth < GeoJSON.maximumNesting else {
                throw .invalid
            }
            var geometries: [GeoGeometry] = []
            for member in try JSONValues.array(object["geometries"]) {
                geometries.append(try geometry(try JSONValues.object(member), depth: depth + 1))
            }
            return .collection(geometries)
        }
        let coordinates = object["coordinates"]
        switch type {
        case "Point": return .point(try position(coordinates))
        case "MultiPoint": return .multiPoint(try positions(coordinates))
        case "LineString": return .lineString(try positions(coordinates))
        case "MultiLineString": return .multiLineString(try lines(coordinates))
        case "Polygon": return .polygon(try lines(coordinates))
        case "MultiPolygon":
            var polygons: [[[GeoPosition]]] = []
            for polygon in try JSONValues.array(coordinates) {
                polygons.append(try lines(polygon))
            }
            return .multiPolygon(polygons)
        default: throw .invalid
        }
    }

    private mutating func lines(_ value: Any?) throws(DiagramDecodingError) -> [[GeoPosition]] {
        var lines: [[GeoPosition]] = []
        for line in try JSONValues.array(value) {
            lines.append(try positions(line))
        }
        return lines
    }

    private mutating func positions(_ value: Any?) throws(DiagramDecodingError) -> [GeoPosition] {
        var positions: [GeoPosition] = []
        for element in try JSONValues.array(value) {
            positions.append(try position(element))
        }
        return positions
    }

    private mutating func position(_ value: Any?) throws(DiagramDecodingError) -> GeoPosition {
        guard limit > 0 else {
            throw .overLimit
        }
        limit -= 1
        let pair = try JSONValues.coordinatePair(value)
        return GeoPosition(longitude: pair.0, latitude: pair.1)
    }
}

/// Typed reads of `JSONSerialization` values, failing with `DiagramDecodingError.invalid`.
enum JSONValues {
    /// The top-level object in `source`.
    static func object(from source: String) throws(DiagramDecodingError) -> [String: Any] {
        guard let data = source.data(using: .utf8),
            let value = try? JSONSerialization.jsonObject(with: data)
        else {
            throw .invalid
        }
        return try object(value)
    }

    static func object(_ value: Any?) throws(DiagramDecodingError) -> [String: Any] {
        guard let object = value as? [String: Any] else {
            throw .invalid
        }
        return object
    }

    static func array(_ value: Any?) throws(DiagramDecodingError) -> [Any] {
        guard let array = value as? [Any] else {
            throw .invalid
        }
        return array
    }

    static func string(_ value: Any?) throws(DiagramDecodingError) -> String {
        guard let string = value as? String else {
            throw .invalid
        }
        return string
    }

    /// A JSON number (never a boolean) as a finite `Double`.
    static func number(_ value: Any?) throws(DiagramDecodingError) -> Double {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue.isFinite
        else {
            throw .invalid
        }
        return number.doubleValue
    }

    /// The first two numbers of an array of at least two numbers.
    static func coordinatePair(_ value: Any?) throws(DiagramDecodingError) -> (Double, Double) {
        let array = try array(value)
        guard array.count >= 2 else {
            throw .invalid
        }
        return (try number(array[0]), try number(array[1]))
    }
}
