/// Draws an STL model (`STL`, `STLProjection`) as a static shaded SVG: no JavaScript, no
/// interactive viewer.
///
/// ```html
/// <svg class="peep-stl" viewBox="0 0 800 400" role="img" aria-label="STL model">
///   <path class="peep-stl-s6" d="M…L…L…Z…"/>  <!-- a run of facets with one shade -->
///   <path class="peep-stl-s2" d="…"/>
/// </svg>
/// ```
///
/// Facets are drawn back to front, and consecutive facets with the same shade share a path, so
/// a convex model needs about one path per shade while a concave one keeps its painter's order.
/// Paths carry classes (`peep-stl-s0`, darkest, to `peep-stl-s7`), never colors: `ThemeBase`
/// colors them from `currentColor`. The model's name is never read, let alone written.
enum STLDiagram {
    /// The class of each shade bucket, darkest first (`STLProjection.shadeCount` of them).
    static let shadeClasses: [StaticString] = [
        "peep-stl-s0", "peep-stl-s1", "peep-stl-s2", "peep-stl-s3",
        "peep-stl-s4", "peep-stl-s5", "peep-stl-s6", "peep-stl-s7",
    ]

    /// The SVG for `triangles`, or `nil` when no facet faces the camera (or a number won't fit).
    static func svg(for triangles: [STLTriangle], label: String) -> String? {
        guard let projection = STLProjection(fitting: triangles) else {
            return nil
        }
        let faces = projection.faces(of: triangles)
        guard !faces.isEmpty else {
            return nil
        }
        var writer = SVGWriter()
        writer.start(
            .svg,
            [
                .class: .keyword("peep-stl"),
                .viewBox: .numbers([0, 0, STLProjection.width, STLProjection.height]),
                .role: .keyword("img"),
                .ariaLabel: .text(label),
            ])
        var run = SVGPath()
        var runShade = faces[0].shade
        for face in faces {
            if face.shade != runShade {
                write(run, shade: runShade, into: &writer)
                run = SVGPath()
                runShade = face.shade
            }
            for (index, corner) in face.corners.enumerated() {
                if index == 0 {
                    run.move(to: corner)
                } else {
                    run.line(to: corner)
                }
            }
            run.close()
        }
        write(run, shade: runShade, into: &writer)
        writer.end()
        return writer.result
    }

    private static func write(_ path: SVGPath, shade: Int, into writer: inout SVGWriter) {
        guard !path.isEmpty, shadeClasses.indices.contains(shade) else {
            return
        }
        writer.empty(.path, [.class: .keyword(shadeClasses[shade]), .pathData: .path(path)])
    }
}
