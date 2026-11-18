import Testing

@testable import PeepCore

@Suite("TopoJSON decoding")
struct TopoJSONTests {
    static func decode(_ json: String, limit: Int = 1000) throws(DiagramDecodingError) -> [GeoGeometry] {
        var limit = limit
        return try TopoJSON.decode(json, coordinateLimit: &limit)
    }

    static func p(_ longitude: Double, _ latitude: Double) -> GeoPosition {
        GeoPosition(longitude: longitude, latitude: latitude)
    }

    /// A topology with `objects` over two arcs: a horizontal line and a square.
    static func topology(_ objects: String, transform: String? = nil) -> String {
        let transform = transform.map { #""transform":\#($0),"# } ?? ""
        return #"{"type":"Topology",\#(transform)"objects":\#(objects),"arcs":[[[0,0],[2,0],[4,0]],"#
            + #"[[4,0],[4,4],[0,4],[0,0]]]}"#
    }

    @Test("quantized arcs are delta-decoded, then scaled and translated")
    func quantizedArcs() throws {
        let json = """
            {"type":"Topology","transform":{"scale":[0.5,2],"translate":[10,-20]},
             "objects":{"a":{"type":"LineString","arcs":[0]}},
             "arcs":[[[0,0],[2,0],[0,3],[-1,-1]]]}
            """
        #expect(try Self.decode(json) == [.lineString([Self.p(10, -20), Self.p(11, -20), Self.p(11, -14), Self.p(10.5, -16)])])
    }

    @Test("without a transform, arcs are absolute positions")
    func absoluteArcs() throws {
        let json = Self.topology(#"{"a":{"type":"LineString","arcs":[0]}}"#)
        #expect(try Self.decode(json) == [.lineString([Self.p(0, 0), Self.p(2, 0), Self.p(4, 0)])])
    }

    @Test("a negative index is the arc ~i reversed, and joined arcs share their point once")
    func reversedAndJoined() throws {
        let p = Self.p
        let reversed = Self.topology(#"{"a":{"type":"LineString","arcs":[-1]}}"#)
        #expect(try Self.decode(reversed) == [.lineString([p(4, 0), p(2, 0), p(0, 0)])])
        // Arc 0 ends at (4, 0) where arc 1 starts.
        let joined = Self.topology(#"{"a":{"type":"Polygon","arcs":[[0,1]]}}"#)
        #expect(try Self.decode(joined) == [.polygon([[p(0, 0), p(2, 0), p(4, 0), p(4, 4), p(0, 4), p(0, 0)]])])
        let backwards = Self.topology(#"{"a":{"type":"Polygon","arcs":[[-2,-1]]}}"#)
        #expect(try Self.decode(backwards) == [.polygon([[p(0, 0), p(0, 4), p(4, 4), p(4, 0), p(2, 0), p(0, 0)]])])
    }

    @Test("every geometry type decodes; objects are drawn in name order; null geometries are skipped")
    func geometryTypes() throws {
        let p = Self.p
        let objects = """
            {"b":{"type":"GeometryCollection","geometries":[
                {"type":"Point","coordinates":[1,2]},
                {"type":"MultiPoint","coordinates":[[1,2],[3,4]]},
                {"type":null},
                {"type":"MultiLineString","arcs":[[0],[-1]]},
                {"type":"MultiPolygon","arcs":[[[1]]]}]},
             "a":{"type":"Point","coordinates":[2,1]}}
            """
        let line = [p(0, 0), p(2, 0), p(4, 0)]
        #expect(
            try Self.decode(Self.topology(objects)) == [
                .point(p(2, 1)),
                .collection([
                    .point(p(1, 2)), .multiPoint([p(1, 2), p(3, 4)]), .multiLineString([line, line.reversed()]),
                    .multiPolygon([[[p(4, 0), p(4, 4), p(0, 4), p(0, 0)]]]),
                ]),
            ])
    }

    @Test("points are quantized but not delta-encoded")
    func quantizedPoints() throws {
        let json = Self.topology(
            #"{"a":{"type":"MultiPoint","coordinates":[[1,1],[1,1]]}}"#,
            transform: #"{"scale":[2,3],"translate":[1,1]}"#)
        #expect(try Self.decode(json) == [.multiPoint([Self.p(3, 4), Self.p(3, 4)])])
    }

    @Test(
        "malformed topologies are rejected",
        arguments: [
            #"{"type":"FeatureCollection","features":[]}"#,
            #"{"type":"Topology","arcs":[]}"#,
            #"{"type":"Topology","objects":{}}"#,
            #"{"type":"Topology","objects":{"a":{"type":"LineString","arcs":[2]}},"arcs":[[[0,0],[1,1]]]}"#,
            #"{"type":"Topology","objects":{"a":{"type":"LineString","arcs":[-2]}},"arcs":[[[0,0],[1,1]]]}"#,
            #"{"type":"Topology","objects":{"a":{"type":"LineString","arcs":[0.5]}},"arcs":[[[0,0],[1,1]]]}"#,
            #"{"type":"Topology","objects":{"a":{"type":"LineString","arcs":[1e300]}},"arcs":[[[0,0],[1,1]]]}"#,
            #"{"type":"Topology","objects":{"a":{"type":"Sphere"}},"arcs":[]}"#,
            #"{"type":"Topology","objects":{"a":1},"arcs":[]}"#,
            #"{"type":"Topology","transform":{"scale":[1]},"objects":{},"arcs":[]}"#,
            #"{"type":"Topology","objects":{},"arcs":[[[0,"x"]]]}"#,
        ])
    func malformed(json: String) {
        #expect(throws: DiagramDecodingError.self) { try Self.decode(json) }
    }

    @Test("drawn positions are charged each time an arc is used")
    func limit() throws {
        let json = Self.topology(#"{"a":{"type":"MultiLineString","arcs":[[0],[0],[0]]}}"#)
        var limit = 100
        _ = try TopoJSON.decode(json, coordinateLimit: &limit)
        #expect(limit == 91)
        #expect(throws: DiagramDecodingError.overLimit) { try Self.decode(json, limit: 8) }
    }
}
