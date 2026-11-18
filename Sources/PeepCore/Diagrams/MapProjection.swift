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
            let point = Self.mercator(position)
            minimumX = min(minimumX, point.horizontal)
            minimumY = min(minimumY, point.vertical)
            maximumX = max(maximumX, point.horizontal)
            maximumY = max(maximumY, point.vertical)
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

    /// `position` in viewBox units.
    func project(_ position: GeoPosition) -> SVGPoint {
        let point = Self.mercator(position)
        return SVGPoint(
            horizontal: originX + (point.horizontal - minimumX) * scale,
            vertical: originY + (point.vertical - minimumY) * scale)
    }

    /// Web Mercator in the unit square: horizontally from 0 (180°W) to 1 (180°E), vertically
    /// from 0 (north) to 1 (south), for latitudes within ±`maximumLatitude`.
    static func mercator(_ position: GeoPosition) -> SVGPoint {
        let latitude = min(max(position.latitude, -maximumLatitude), maximumLatitude) * .pi / 180
        return SVGPoint(
            horizontal: (position.longitude + 180) / 360, vertical: (1 - log(tan(.pi / 4 + latitude / 2)) / .pi) / 2)
    }
}
