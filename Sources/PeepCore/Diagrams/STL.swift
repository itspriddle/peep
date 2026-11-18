/// A point or direction in a model's space, in STL units: `east`, `north`, and `upward` are the
/// file's x, y, and z (z is up, as CAD exporters write it).
struct STLVector: Sendable, Equatable {
    var east: Double
    var north: Double
    var upward: Double

    static func - (lhs: Self, rhs: Self) -> Self {
        STLVector(east: lhs.east - rhs.east, north: lhs.north - rhs.north, upward: lhs.upward - rhs.upward)
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        STLVector(east: lhs.east + rhs.east, north: lhs.north + rhs.north, upward: lhs.upward + rhs.upward)
    }

    static func * (lhs: Self, rhs: Double) -> Self {
        STLVector(east: lhs.east * rhs, north: lhs.north * rhs, upward: lhs.upward * rhs)
    }

    func dot(_ other: Self) -> Double {
        east * other.east + north * other.north + upward * other.upward
    }

    func cross(_ other: Self) -> Self {
        STLVector(
            east: north * other.upward - upward * other.north,
            north: upward * other.east - east * other.upward,
            upward: east * other.north - north * other.east)
    }

    var length: Double {
        dot(self).squareRoot()
    }

    /// The unit vector along this one, or `nil` for a zero (or non-finite) vector.
    var normalized: Self? {
        let length = length
        guard length.isFinite, length > 0 else {
            return nil
        }
        return self * (1 / length)
    }
}

/// One facet: three vertices, counterclockwise seen from outside (STL's rule). The file's
/// normal isn't kept; `STLProjection` recomputes it from the vertices.
struct STLTriangle: Sendable, Equatable {
    var first: STLVector
    var second: STLVector
    var third: STLVector

    /// The outward normal by the right-hand rule, or `nil` for a degenerate facet.
    var normal: STLVector? {
        (second - first).cross(third - first).normalized
    }
}

/// Decodes ASCII STL into triangles, one line at a time:
///
/// ```
/// solid name
///   facet normal ni nj nk
///     outer loop
///       vertex x y z      (three times)
///     endloop
///   endfacet
/// endsolid name
/// ```
///
/// Tolerant the way real exporters need: keywords in any case, any spaces or tabs, blank lines,
/// CRLF, several solids in a row, and a facet's normal missing or not a number (it's recomputed).
/// Strict about the structure: anything else, a vertex that isn't three finite numbers, or no
/// facets at all is `.invalid`, and the block stays code. Names after `solid` and `endsolid`
/// are never read.
enum STL {
    /// The most facets one block may hold (`DiagramKind.render` also stops at the document's
    /// coordinate budget).
    static let maximumTriangles = 50_000
    /// What a facet costs against `DiagramBudget.coordinates`: its three vertices.
    static let coordinatesPerTriangle = 3

    /// The facets in `source`; `.overLimit` past `triangleLimit` of them.
    static func decode(_ source: String, triangleLimit: Int) throws(DiagramDecodingError) -> [STLTriangle] {
        var parser = Parser(limit: triangleLimit)
        for line in source.utf8.split(whereSeparator: { $0 == newline || $0 == carriageReturn }) {
            let words = line.split(whereSeparator: isSpace)
            if let keyword = words.first {
                try parser.read(keyword: keyword, arguments: words.dropFirst())
            }
        }
        return try parser.finish()
    }

    private static let newline = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == 0x0B || byte == 0x0C
    }

    private typealias Word = Substring.UTF8View.SubSequence

    /// Where the parser is: what the next line may be.
    private enum State {
        /// Before the first solid, or after an `endsolid`: `solid` (or the end).
        case outside
        /// Inside a solid: `facet` or `endsolid`.
        case solid
        /// After `facet`: `outer loop`.
        case facet
        /// Inside the loop: `vertex` until there are three, then `endloop`.
        case loop([STLVector])
        /// After `endloop`: `endfacet`.
        case loopEnded
    }

    private struct Parser {
        let limit: Int
        var state = State.outside
        var triangles: [STLTriangle] = []

        init(limit: Int) {
            self.limit = limit
        }

        mutating func read(keyword: Word, arguments: ArraySlice<Word>) throws(DiagramDecodingError) {
            switch state {
            case .outside:
                try expect(keyword, "solid")
                state = .solid
            case .solid:
                if STL.matches(keyword, "endsolid") {
                    state = .outside
                } else {
                    try expect(keyword, "facet")
                    guard triangles.count < limit else {
                        throw .overLimit
                    }
                    state = .facet
                }
            case .facet:
                try expect(keyword, "outer")
                guard arguments.count == 1, let loop = arguments.first, STL.matches(loop, "loop") else {
                    throw .invalid
                }
                state = .loop([])
            case .loop(var vertices):
                if vertices.count == 3 {
                    try expect(keyword, "endloop")
                    guard arguments.isEmpty else {
                        throw .invalid
                    }
                    triangles.append(STLTriangle(first: vertices[0], second: vertices[1], third: vertices[2]))
                    state = .loopEnded
                } else {
                    try expect(keyword, "vertex")
                    vertices.append(try Self.vertex(arguments))
                    state = .loop(vertices)
                }
            case .loopEnded:
                try expect(keyword, "endfacet")
                guard arguments.isEmpty else {
                    throw .invalid
                }
                state = .solid
            }
        }

        func finish() throws(DiagramDecodingError) -> [STLTriangle] {
            guard case .outside = state, !triangles.isEmpty else {
                throw .invalid
            }
            return triangles
        }

        private func expect(_ word: Word, _ keyword: StaticString) throws(DiagramDecodingError) {
            guard STL.matches(word, keyword) else {
                throw .invalid
            }
        }

        private static func vertex(_ arguments: ArraySlice<Word>) throws(DiagramDecodingError) -> STLVector {
            guard arguments.count == 3 else {
                throw .invalid
            }
            var numbers: [Double] = []
            for word in arguments {
                guard let text = String(word), let number = Double(text), number.isFinite else {
                    throw .invalid
                }
                numbers.append(number)
            }
            return STLVector(east: numbers[0], north: numbers[1], upward: numbers[2])
        }
    }

    /// Whether `word` is `keyword` (lowercase ASCII), in any case.
    private static func matches(_ word: Word, _ keyword: StaticString) -> Bool {
        guard word.count == keyword.utf8CodeUnitCount else {
            return false
        }
        let expected = UnsafeBufferPointer(start: keyword.utf8Start, count: keyword.utf8CodeUnitCount)
        return zip(word, expected).allSatisfy { byte, letter in
            let lowered = byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z") ? byte | 0x20 : byte
            return lowered == letter
        }
    }
}
