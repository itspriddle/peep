/// The fenced code block languages Peep draws as diagrams (M7), named by the info string's first
/// word, case-insensitive (` ```geojson `, ` ```TopoJSON `).
///
/// A kind is one case here plus its `render(_:budget:)` branch: `DiagramRendering` handles the
/// caps and the AST, `HTMLRenderer` the `<figure>` around the SVG, `ThemeBase` the styling of
/// the classes it emits.
enum DiagramKind: String, CaseIterable, Sendable {
    case geojson
    case topojson

    /// The kind `language` names, or `nil` for any other language.
    init?(language: String?) {
        guard let language, let kind = DiagramKind(rawValue: language.lowercased()) else {
            return nil
        }
        self = kind
    }

    /// The figure's modifier class (`peep-diagram-<kind>`), beside `peep-diagram`.
    var figureClass: String {
        "peep-diagram-\(rawValue)"
    }

    /// The SVG's accessible name and the figure's (visually hidden) caption.
    var label: String {
        switch self {
        case .geojson: "GeoJSON map"
        case .topojson: "TopoJSON map"
        }
    }

    /// The `<svg>` for `source`, or `nil` to show the block as code: unreadable input, an empty
    /// drawing, or more than `budget.coordinates` coordinates. Charges `budget` only on success.
    func render(_ source: String, budget: inout DiagramBudget) -> String? {
        switch self {
        case .geojson, .topojson:
            var limit = budget.coordinates
            let geometries =
                self == .geojson
                ? try? GeoJSON.decode(source, coordinateLimit: &limit)
                : try? TopoJSON.decode(source, coordinateLimit: &limit)
            guard let geometries, let svg = MapDiagram.svg(for: geometries, label: label) else {
                return nil
            }
            budget.coordinates = limit
            return svg
        }
    }
}

/// What is left of a document's diagram allowance (`DiagramRendering.documentCoordinateBudget`).
struct DiagramBudget: Sendable, Equatable {
    /// Coordinates (map positions, later model vertices) still allowed in this document.
    var coordinates: Int
}
