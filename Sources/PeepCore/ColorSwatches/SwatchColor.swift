/// A color written as the whole of an inline code span, as GitHub shows a swatch for in issues
/// and comments (`ColorSwatches`).
///
/// The accepted forms are GitHub's (checked against `gh api markdown`), not all of CSS:
///
/// - `#RRGGBB`, any case. Not `#RGB` or `#RRGGBBAA`.
/// - `rgb(R, G, B)` and `rgba(R, G, B, A)`: plain decimal numbers (`9`, `9.5`, `.5`), no `%`.
/// - `hsl(H, S%, L%)`: plain numbers, `%` required on saturation and lightness. No `hsla`.
///
/// Function names are lowercase; spaces may surround each argument, never the `(`. Values out
/// of range are accepted and clamped as CSS clamps them (`rgb(300, 0, 0)` is red). The color is
/// kept as bytes, so the page only ever sees `hex`, never the document's text.
public struct SwatchColor: Sendable, Equatable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    /// 255 is opaque.
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Longer code spans are never colors; keeps the scan trivial for huge spans.
    static let maximumLength = 64

    /// The color `text` names, or `nil` when the whole of it isn't one of the accepted forms.
    public init?(parsing text: String) {
        let bytes = Array(text.utf8)
        guard bytes.count <= Self.maximumLength, let first = bytes.first else {
            return nil
        }
        let color = first == UInt8(ascii: "#") ? Self.hex(bytes) : Self.function(bytes)
        guard let color else {
            return nil
        }
        self = color
    }

    /// `#rrggbb`, or `#rrggbbaa` when not opaque: safe to write into a `style` attribute.
    public var hex: String {
        let bytes = alpha == 255 ? [red, green, blue] : [red, green, blue, alpha]
        return "#"
            + bytes.map { byte in
                let digits = String(byte, radix: 16)
                return digits.count == 1 ? "0" + digits : digits
            }.joined()
    }

    // MARK: Parsing

    private static func hex(_ bytes: [UInt8]) -> SwatchColor? {
        guard bytes.count == 7 else {
            return nil
        }
        var values: [UInt8] = []
        for index in stride(from: 1, to: 7, by: 2) {
            guard let high = hexValue(bytes[index]), let low = hexValue(bytes[index + 1]) else {
                return nil
            }
            values.append(high << 4 | low)
        }
        return SwatchColor(red: values[0], green: values[1], blue: values[2])
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        default: nil
        }
    }

    /// `name(arg, …)`: the name up to `(`, then the arguments up to a final `)`.
    private static func function(_ bytes: [UInt8]) -> SwatchColor? {
        guard let open = bytes.firstIndex(of: UInt8(ascii: "(")), bytes.last == UInt8(ascii: ")"),
            let name = String(bytes: bytes[..<open], encoding: .utf8)
        else {
            return nil
        }
        let arguments = bytes[(open + 1)..<(bytes.count - 1)]
            .split(separator: UInt8(ascii: ","), omittingEmptySubsequences: false)
            .map(trimmingSpaces)
        switch name {
        case "rgb" where arguments.count == 3, "rgba" where arguments.count == 4:
            let numbers = arguments.compactMap(number)
            guard numbers.count == arguments.count else {
                return nil
            }
            let alpha = numbers.count == 4 ? clampedByte(numbers[3] * 255) : 255
            return SwatchColor(
                red: clampedByte(numbers[0]), green: clampedByte(numbers[1]), blue: clampedByte(numbers[2]),
                alpha: alpha)
        case "hsl" where arguments.count == 3:
            guard let hue = number(arguments[0]), let saturation = percentage(arguments[1]),
                let lightness = percentage(arguments[2])
            else {
                return nil
            }
            return fromHSL(hue: hue, saturation: saturation, lightness: lightness)
        default:
            return nil
        }
    }

    private static func trimmingSpaces(_ bytes: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        let space = UInt8(ascii: " ")
        guard let start = bytes.firstIndex(where: { $0 != space }),
            let end = bytes.lastIndex(where: { $0 != space })
        else {
            return []
        }
        return bytes[start...end]
    }

    /// Digits with an optional fraction (`9`, `9.5`, `.5`). No sign, exponent, or unit.
    private static func number(_ bytes: ArraySlice<UInt8>) -> Double? {
        let parts = bytes.split(separator: UInt8(ascii: "."), maxSplits: 1, omittingEmptySubsequences: false)
        let isDigits = { (part: ArraySlice<UInt8>) in
            part.allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }
        }
        guard !bytes.isEmpty, parts.allSatisfy(isDigits), parts.count == 1 || !parts[1].isEmpty,
            let text = String(bytes: bytes, encoding: .ascii)
        else {
            return nil
        }
        return Double(text.first == "." ? "0" + text : text)
    }

    /// A `number` followed by `%`, as a fraction (`45%` is 0.45).
    private static func percentage(_ bytes: ArraySlice<UInt8>) -> Double? {
        guard bytes.last == UInt8(ascii: "%"), let value = number(bytes.dropLast()) else {
            return nil
        }
        return value / 100
    }

    private static func clampedByte(_ value: Double) -> UInt8 {
        UInt8(min(max(value.rounded(), 0), 255))
    }

    /// CSS Color 4's HSL to sRGB conversion, after clamping saturation and lightness to 0…1.
    private static func fromHSL(hue: Double, saturation: Double, lightness: Double) -> SwatchColor {
        let hue = hue.truncatingRemainder(dividingBy: 360)
        let saturation = min(max(saturation, 0), 1)
        let lightness = min(max(lightness, 0), 1)
        let chroma = saturation * min(lightness, 1 - lightness)
        let channel = { (offset: Double) -> UInt8 in
            let sector = (offset + hue / 30).truncatingRemainder(dividingBy: 12)
            let value = lightness - chroma * max(-1, min(sector - 3, 9 - sector, 1))
            return clampedByte(value * 255)
        }
        return SwatchColor(red: channel(0), green: channel(8), blue: channel(4))
    }
}
