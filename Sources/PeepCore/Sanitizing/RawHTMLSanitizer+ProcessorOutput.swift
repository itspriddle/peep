/// What `HTMLSanitizerMode.processorOutput` adds to the raw-HTML rules (#106).
extension RawHTMLSanitizer {
    func allowsElement(_ name: String) -> Bool {
        HTMLSanitizerPolicy.elements.contains(name)
            || (mode == .processorOutput && HTMLSanitizerPolicy.ProcessorOutput.elements.contains(name))
    }

    /// A processor's task-list checkbox (`HTMLSanitizerMode.processorOutput`), always disabled
    /// so the reader can't toggle it; any other `<input>` is removed.
    func checkbox(_ tag: HTMLStartTag) -> String {
        func value(of name: String) -> AttributeValue? {
            tag.attributes.first { $0.name == name }?.value.map(AttributeValue.init)
        }
        guard value(of: "type")?.decoded.lowercased() == "checkbox" else {
            return ""
        }
        var output = "<input type=\"checkbox\""
        if let classes = value(of: "class") {
            output += Self.classAttribute(classes)
        }
        if tag.attributes.contains(where: { $0.name == "checked" }) {
            output += " checked"
        }
        return output + (tag.isSelfClosing ? " disabled />" : " disabled>")
    }

    func allowsAttribute(_ attribute: String, on element: String) -> Bool {
        HTMLSanitizerPolicy.allowsAttribute(attribute, on: element)
            || (mode == .processorOutput && attribute == "class")
    }

    /// ` class="…"` with Peep's reserved names removed, or nothing when none are left.
    static func classAttribute(_ value: AttributeValue) -> String {
        guard let classes = HTMLSanitizerPolicy.ProcessorOutput.allowedClasses(value.decoded) else {
            return ""
        }
        return " class=\"\(HTMLDocument.escape(classes))\""
    }
}
