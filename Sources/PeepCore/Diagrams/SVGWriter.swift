/// Writes the SVG for a diagram. Renderer output is trusted (`HTMLRenderer` writes it
/// verbatim), so this is the one place diagram markup is made, and it is safe by construction:
///
/// - element and attribute names are the fixed cases of `SVGElement` and `SVGAttribute`;
/// - values are literals in Peep's source (`SVGValue.keyword`), text escaped like the rest of
///   the renderer's output (`SVGValue.text`, `HTMLOutput.text`), or finite numbers formatted
///   here (`SVGValue.numbers`, `SVGPath`). A non-finite number makes the whole result `nil`.
///
/// No input string is ever written as markup.
struct SVGWriter {
    private var output = HTMLOutput()
    private var openElements: [SVGElement] = []
    private var isValid = true

    /// The markup, or `nil` when an element is still open or a value wasn't finite.
    var result: String? {
        isValid && openElements.isEmpty ? output.string : nil
    }

    /// Writes `<element attributes…>`; close it with `end()`.
    mutating func start(_ element: SVGElement, _ attributes: KeyValuePairs<SVGAttribute, SVGValue> = [:]) {
        writeTag(element, attributes)
        output.raw(">")
        openElements.append(element)
    }

    /// Writes `<element attributes…/>`.
    mutating func empty(_ element: SVGElement, _ attributes: KeyValuePairs<SVGAttribute, SVGValue> = [:]) {
        writeTag(element, attributes)
        output.raw("/>")
    }

    /// Closes the innermost open element.
    mutating func end() {
        guard let element = openElements.popLast() else {
            isValid = false
            return
        }
        output.raw("</\(element.rawValue)>")
    }

    private mutating func writeTag(_ element: SVGElement, _ attributes: KeyValuePairs<SVGAttribute, SVGValue>) {
        output.raw("<\(element.rawValue)")
        for (name, value) in attributes {
            output.raw(" \(name.rawValue)=\"")
            switch value {
            case .keyword(let keyword):
                output.text(keyword.description)
            case .text(let text):
                output.text(text)
            case .numbers(let numbers):
                let formatted = numbers.map(SVGNumber.format)
                if formatted.contains(nil) {
                    isValid = false
                }
                output.raw(formatted.compactMap(\.self).joined(separator: " "))
            case .path(let path):
                if !path.isValid {
                    isValid = false
                }
                output.raw(path.data)
            }
            output.raw("\"")
        }
    }
}

/// The SVG elements `SVGWriter` writes.
enum SVGElement: String, Sendable {
    case svg
    case path
}

/// The attributes `SVGWriter` writes.
enum SVGAttribute: String, Sendable {
    case `class`
    case viewBox
    case role
    case ariaLabel = "aria-label"
    case fillRule = "fill-rule"
    case pathData = "d"
}

/// An attribute value.
enum SVGValue: Sendable {
    /// A literal in Peep's source (class names, roles); escaped anyway.
    case keyword(StaticString)
    /// Any other text, escaped.
    case text(String)
    /// Finite numbers, formatted and separated by spaces.
    case numbers([Double])
    /// Path data.
    case path(SVGPath)
}

/// A point in a drawing's viewBox units: `horizontal` grows rightward, `vertical` downward.
struct SVGPoint: Sendable, Equatable {
    var horizontal: Double
    var vertical: Double
}

/// Path data (`d`), made only of commands and `SVGNumber`s. Points are rounded to a tenth of a
/// unit, and a point that rounds to the one before it is dropped, so dense input doesn't make
/// longer output than the drawing can show.
struct SVGPath: Sendable {
    private(set) var data = ""
    /// `false` once a non-finite number was given; `SVGWriter` then writes nothing.
    private(set) var isValid = true
    /// The current point as written, while a subpath is open.
    private var current: FormattedPoint?

    var isEmpty: Bool {
        data.isEmpty
    }

    /// Starts a subpath at `point`.
    mutating func move(to point: SVGPoint) {
        guard let formatted = format(point) else {
            return
        }
        data += "M\(formatted)"
        current = formatted
    }

    /// A line from the current point to `point` (a move without one); skipped when it rounds to
    /// the current point.
    mutating func line(to point: SVGPoint) {
        guard let current else {
            move(to: point)
            return
        }
        guard let formatted = format(point), formatted != current else {
            return
        }
        data += "L\(formatted)"
        self.current = formatted
    }

    /// Closes the current subpath.
    mutating func close() {
        guard current != nil else {
            return
        }
        data += "Z"
        current = nil
    }

    /// A filled circle of `radius` around `center`, as two arcs (one path can hold many).
    mutating func dot(at center: SVGPoint, radius: Double) {
        guard
            let start = format(SVGPoint(horizontal: center.horizontal - radius, vertical: center.vertical)),
            let size = SVGNumber.format(radius), let diameter = SVGNumber.format(radius * 2)
        else {
            isValid = false
            return
        }
        data += "M\(start)a\(size) \(size) 0 1 0 \(diameter) 0a\(size) \(size) 0 1 0 -\(diameter) 0Z"
        current = nil
    }

    private mutating func format(_ point: SVGPoint) -> FormattedPoint? {
        guard let horizontal = SVGNumber.format(point.horizontal), let vertical = SVGNumber.format(point.vertical)
        else {
            isValid = false
            return nil
        }
        return FormattedPoint(horizontal: horizontal, vertical: vertical)
    }
}

/// A point as `SVGNumber`s, written `h v`.
private struct FormattedPoint: Sendable, Equatable, CustomStringConvertible {
    var horizontal: String
    var vertical: String

    var description: String {
        "\(horizontal) \(vertical)"
    }
}

/// Number formatting for SVG: a finite value rounded to one decimal place, without a trailing
/// `.0`, never in exponent form or localized.
enum SVGNumber {
    /// Values beyond this are refused; diagrams stay within a viewBox of a few hundred units.
    static let maximumMagnitude = 1e9

    /// `value` as `-12.3`, `4`, or `0`, or `nil` when it isn't finite or is too large.
    static func format(_ value: Double) -> String? {
        guard value.isFinite, abs(value) <= maximumMagnitude else {
            return nil
        }
        let tenths = Int((value * 10).rounded())
        let magnitude = tenths.magnitude
        let sign = tenths < 0 ? "-" : ""
        let whole = magnitude / 10
        let fraction = magnitude % 10
        return fraction == 0 ? "\(sign)\(whole)" : "\(sign)\(whole).\(fraction)"
    }
}
