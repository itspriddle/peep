/// Projects an STL model for a static drawing: a fixed three-quarter isometric view (from the
/// front right, above), orthographic, fitted to the viewBox.
///
/// - The camera looks along `-viewDirection`: from +east, -north (the front, in Z-up CAD), and
///   above, at the true isometric angle. Models aren't rotated.
/// - Back faces are culled: a facet whose recomputed normal (right-hand rule over its
///   vertices) points away from the camera isn't drawn, nor is a degenerate one.
/// - The rest are sorted back to front (painter's algorithm, by centroid depth; ties keep file
///   order) and shaded by Lambert's law against a fixed light, quantized to `shadeCount`
///   buckets (0 darkest), which `ThemeBase` colors.
/// - The model is fitted to every vertex: centered in a `width` by `height` viewBox with
///   `padding` on every side, at the largest scale that fits both ways. A model whose vertices
///   are all one point (or too large to measure) has no projection.
struct STLProjection: Sendable {
    static let width = 800.0
    static let height = 400.0
    static let padding = 16.0
    static let shadeCount = 8

    /// Toward the camera.
    static let viewDirection = STLVector(east: 1, north: -1, upward: 1) * (1 / 3.0.squareRoot())
    /// The screen's rightward axis.
    static let screenRight = STLVector(east: 1, north: 1, upward: 0) * (1 / 2.0.squareRoot())
    /// The screen's upward axis (SVG's vertical is its opposite).
    static let screenUp = STLVector(east: -1, north: 1, upward: 2) * (1 / 6.0.squareRoot())
    /// Toward the light: above, a little to the front and right, so a box's top, front, and
    /// right sides get three different shades.
    static let lightDirection = STLVector(east: 0.25, north: -0.45, upward: 1) * (1 / 1.2625.squareRoot())

    /// A facet as drawn: its corners in viewBox units and its shade bucket.
    struct Face: Sendable, Equatable {
        var corners: [SVGPoint]
        var shade: Int
    }

    /// A visible face with its sort key: depth toward the camera, then file order.
    private struct SortedFace {
        var depth: Double
        var index: Int
        var face: Face
    }

    private let scale: Double
    private let originX: Double
    private let originY: Double

    /// The projection fitting `triangles`, or `nil` when they span no area on screen.
    init?(fitting triangles: [STLTriangle]) {
        var minimumX = Double.infinity
        var minimumY = Double.infinity
        var maximumX = -Double.infinity
        var maximumY = -Double.infinity
        for triangle in triangles {
            for vertex in [triangle.first, triangle.second, triangle.third] {
                let horizontal = vertex.dot(Self.screenRight)
                let vertical = -vertex.dot(Self.screenUp)
                minimumX = min(minimumX, horizontal)
                minimumY = min(minimumY, vertical)
                maximumX = max(maximumX, horizontal)
                maximumY = max(maximumY, vertical)
            }
        }
        let spanX = maximumX - minimumX
        let spanY = maximumY - minimumY
        guard spanX.isFinite, spanY.isFinite, spanX > 0 || spanY > 0 else {
            return nil
        }
        let availableWidth = Self.width - 2 * Self.padding
        let availableHeight = Self.height - 2 * Self.padding
        let scale = min(
            spanX > 0 ? availableWidth / spanX : .infinity, spanY > 0 ? availableHeight / spanY : .infinity)
        guard scale.isFinite, scale > 0 else {
            return nil
        }
        self.scale = scale
        originX = Self.padding + (availableWidth - spanX * scale) / 2 - minimumX * scale
        originY = Self.padding + (availableHeight - spanY * scale) / 2 - minimumY * scale
    }

    /// `vertex` in viewBox units.
    func project(_ vertex: STLVector) -> SVGPoint {
        SVGPoint(
            horizontal: originX + vertex.dot(Self.screenRight) * scale,
            vertical: originY - vertex.dot(Self.screenUp) * scale)
    }

    /// The facets facing the camera, back to front, with their shades.
    func faces(of triangles: [STLTriangle]) -> [Face] {
        var visible: [SortedFace] = []
        for (index, triangle) in triangles.enumerated() {
            guard let normal = triangle.normal, normal.dot(Self.viewDirection) > 0 else {
                continue
            }
            let centroid = (triangle.first + triangle.second + triangle.third) * (1 / 3)
            let depth = centroid.dot(Self.viewDirection)
            guard depth.isFinite else {
                continue
            }
            let face = Face(
                corners: [project(triangle.first), project(triangle.second), project(triangle.third)],
                shade: Self.shade(of: normal))
            visible.append(SortedFace(depth: depth, index: index, face: face))
        }
        visible.sort { ($0.depth, $0.index) < ($1.depth, $1.index) }
        return visible.map(\.face)
    }

    /// The bucket for a facet with `normal`: Lambert's cosine against `lightDirection`, from 0
    /// (lit edge-on or from behind) to `shadeCount - 1` (facing the light).
    static func shade(of normal: STLVector) -> Int {
        let intensity = max(0, normal.dot(lightDirection))
        return min(shadeCount - 1, Int(intensity * Double(shadeCount)))
    }
}
