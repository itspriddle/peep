/// Which custom program a run belongs to: both share one runner (`CustomProgramRunner`), its
/// contract, and its limits, and differ in where their output goes.
public enum CustomProgramKind: Sendable, Equatable {
    /// `CustomPreprocessor` (#56): Markdown in, Markdown out, before frontmatter is read.
    case preprocessor
    /// `CustomProcessor` (#106): the Markdown body in, an HTML fragment out, in place of the
    /// built-in renderer.
    case processor

    /// The program's name in messages, lowercase: "preprocessor", "processor".
    public var noun: String {
        switch self {
        case .preprocessor: "preprocessor"
        case .processor: "processor"
        }
    }

    /// The logger category and thread name suffix.
    var identifier: String {
        noun
    }
}
