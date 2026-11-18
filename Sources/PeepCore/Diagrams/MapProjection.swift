import Foundation

/// Web Mercator (the projection of web map tiles, and so of GitHub's maps), fitted to a drawing's
/// bounds: the shapes are centered in a `width` by `height` viewBox with `padding` on every
/// side, at the largest scale that fits both ways.
///
/// - Latitude is clamped to ±`maximumLatitude`, where Web Mercator's square ends (the poles
///   are infinitely far away).
/// - Longitude isn't wrapped, and shapes that cross the antimeridian aren't split: a shape from
///   179° to -179° spans the whole map rather than 2°, as its coordinates say.
/// - A drawing smaller than `minimumSpan` (a single point, a short line) is shown at the scale
///   that span would get, centered, rather than infinitely zoomed in.
struct MapProjection: Sendable, Equatable {
    static let maximumLatitude = 85.0511
    static let width = 800.0
    static let height = 400.0
    static let padding = 16.0
    /// The smallest extent fitted, in Mercator units (the world is 1 wide): about 0.004° of
    /// longitude, a few hundred meters.
    static let minimumSpan = 1e-5

    private let minimumX: Double
    private let minimumY: Double
    private let scale: Double
    private let originX: Double
    private let originY: Double

    /// The projection fitting `positions`, or `nil` when there are none.
    init?(fitting positions: some Sequence<GeoPosition>) {
        var minimumX = Double.infinity
        var minimumY = Double.infinity
        var maximumX = -Double.infinity
        var maximumY = -Double.infinity
        for position in positions {
            let (x, y) = Self.mercator(position)
            minimumX = min(minimumX, x)
            minimumY = min(minimumY, y)
            maximumX = max(maximumX, x)
            maximumY = max(maximumY, y)
        }
        guard minimumX <= maximumX, minimumY <= maximumY else {
            return nil
        }
        let spanX = maximumX - minimumX
        let spanY = maximumY - minimumY
        let availableWidth = Self.width - 2 * Self.padding
        let availableHeight = Self.height - 2 * Self.padding
        let scale = min(
            availableWidth / max(spanX, Self.minimumSpan), availableHeight / max(spanY, Self.minimumSpan))
        self.minimumX = minimumX
        self.minimumY = minimumY
        self.scale = scale
        originX = Self.padding + (availableWidth - spanX * scale) / 2
        originY = Self.padding + (availableHeight - spanY * scale) / 2
    }

    /// `position` in viewBox units (y grows downward).
    func project(_ position: GeoPosition) -> (x: Double, y: Double) {
        let (x, y) = Self.mercator(position)
        return (originX + (x - minimumX) * scale, originY + (y - minimumY) * scale)
    }

    /// Web Mercator in the unit square: x from 0 (180°W) to 1 (180°E), y from 0 (north) to 1
    /// (south), for latitudes within ±`maximumLatitude`.
    static func mercator(_ position: GeoPosition) -> (x: Double, y: Double) {
        let latitude = min(max(position.latitude, -maximumLatitude), maximumLatitude) * .pi / 180
        let x = (position.longitude + 180) / 360
        let y = (1 - log(tan(.pi / 4 + latitude / 2)) / .pi) / 2
        return (x, y)
    }
}
