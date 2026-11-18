import Testing

@testable import PeepCore

@Suite("GeoJSON decoding")
struct GeoJSONTests {
    static func decode(_ json: String, limit: Int = 1000) throws(DiagramDecodingError) -> [GeoGeometry] {
        var limit = limit
        return try GeoJSON.decode(json, coordinateLimit: &limit)
    }

    static func position(_ longitude: Double, _ latitude: Double) -> GeoPosition {
        GeoPosition(longitude: longitude, latitude: latitude)
    }

    @Test("every geometry type decodes")
    func geometryTypes() throws {
        let p = Self.position
        #expect(try Self.decode(#"{"type":"Point","coordinates":[1,2]}"#) == [.point(p(1, 2))])
        #expect(
            try Self.decode(#"{"type":"MultiPoint","coordinates":[[1,2],[3,4]]}"#) == [.multiPoint([p(1, 2), p(3, 4)])])
        #expect(
            try Self.decode(#"{"type":"LineString","coordinates":[[1,2],[3,4]]}"#) == [.lineString([p(1, 2), p(3, 4)])])
        #expect(
            try Self.decode(#"{"type":"MultiLineString","coordinates":[[[1,2],[3,4]],[[5,6],[7,8]]]}"#)
                == [.multiLineString([[p(1, 2), p(3, 4)], [p(5, 6), p(7, 8)]])])
        let square = [p(0, 0), p(4, 0), p(4, 4), p(0, 4), p(0, 0)]
        let hole = [p(1, 1), p(1, 2), p(2, 2), p(1, 1)]
        #expect(
            try Self.decode(
                #"{"type":"Polygon","coordinates":[[[0,0],[4,0],[4,4],[0,4],[0,0]],[[1,1],[1,2],[2,2],[1,1]]]}"#)
                == [.polygon([square, hole])])
        #expect(
            try Self.decode(
                #"{"type":"MultiPolygon","coordinates":[[[[0,0],[4,0],[4,4],[0,4],[0,0]]],[[[1,1],[1,2],[2,2],[1,1]]]]}"#)
                == [.multiPolygon([[square], [hole]])])
        #expect(
            try Self.decode(
                #"{"type":"GeometryCollection","geometries":[{"type":"Point","coordinates":[1,2]},"#
                    + #"{"type":"GeometryCollection","geometries":[{"type":"LineString","coordinates":[[1,2],[3,4]]}]}]}"#)
                == [.collection([.point(p(1, 2)), .collection([.lineString([p(1, 2), p(3, 4)])])])])
    }

    @Test("a Feature and a FeatureCollection give their geometries; null geometries are skipped")
    func features() throws {
        let p = Self.position
        #expect(
            try Self.decode(#"{"type":"Feature","properties":{"a":1},"geometry":{"type":"Point","coordinates":[1,2]}}"#)
                == [.point(p(1, 2))])
        #expect(try Self.decode(#"{"type":"Feature","properties":null,"geometry":null}"#).isEmpty)
        let collection = """
            {"type":"FeatureCollection","features":[
              {"type":"Feature","id":7,"properties":{},"geometry":{"type":"Point","coordinates":[1,2]}},
              {"type":"Feature","properties":{},"geometry":null},
              {"type":"Feature","geometry":{"type":"Point","coordinates":[3,4]},"foreign":[1,2]}
            ]}
            """
        #expect(try Self.decode(collection) == [.point(p(1, 2)), .point(p(3, 4))])
        #expect(try Self.decode(#"{"type":"FeatureCollection","features":[]}"#).isEmpty)
    }

    @Test("altitude and later position members are dropped")
    func altitude() throws {
        #expect(try Self.decode(#"{"type":"Point","coordinates":[1.5,-2.25,100,7]}"#) == [.point(Self.position(1.5, -2.25))])
    }

    @Test(
        "malformed input is rejected",
        arguments: [
            "not json",
            "[1, 2]",
            "\"Point\"",
            #"{"coordinates":[1,2]}"#,
            #"{"type":"Circle","coordinates":[1,2]}"#,
            #"{"type":"Point"}"#,
            #"{"type":"Point","coordinates":[1]}"#,
            #"{"type":"Point","coordinates":["1","2"]}"#,
            #"{"type":"Point","coordinates":[true,false]}"#,
            #"{"type":"Point","coordinates":[1,null]}"#,
            #"{"type":"LineString","coordinates":[1,2]}"#,
            #"{"type":"Polygon","coordinates":[[1,2]]}"#,
            #"{"type":"Feature","geometry":{"type":"Point","coordinates":{}}}"#,
            #"{"type":"FeatureCollection","features":[{"type":"Point","coordinates":[1,2]}]}"#,
            #"{"type":"FeatureCollection"}"#,
            #"{"type":"GeometryCollection","geometries":[1]}"#,
            #"{"type":"Point","coordinates":[1e999,2]}"#,
        ])
    func malformed(json: String) {
        #expect(throws: DiagramDecodingError.self) { try Self.decode(json) }
    }

    @Test("collections nested past the limit are rejected")
    func nesting() {
        func nested(_ depth: Int) -> String {
            String(repeating: #"{"type":"GeometryCollection","geometries":["#, count: depth)
                + #"{"type":"Point","coordinates":[1,2]}"# + String(repeating: "]}", count: depth)
        }
        #expect((try? Self.decode(nested(GeoJSON.maximumNesting))) != nil)
        #expect(throws: DiagramDecodingError.invalid) { try Self.decode(nested(GeoJSON.maximumNesting + 1)) }
    }

    @Test("positions are charged against the limit, and going over fails")
    func limit() throws {
        var limit = 10
        _ = try GeoJSON.decode(#"{"type":"LineString","coordinates":[[1,2],[3,4],[5,6]]}"#, coordinateLimit: &limit)
        #expect(limit == 7)
        #expect(throws: DiagramDecodingError.overLimit) {
            try Self.decode(#"{"type":"LineString","coordinates":[[1,2],[3,4],[5,6]]}"#, limit: 2)
        }
    }
}
