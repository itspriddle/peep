import PeepCore

/// What the app says about each custom program (Settings, the failure bar, the Open panel), and
/// the accessibility identifier prefix UI tests find them by: `settings-custom-<noun>…` and
/// `<noun>-failure-…`.
extension CustomProgramKind {
    /// Settings > Markdown's section title.
    var sectionTitle: String {
        switch self {
        case .preprocessor: "Custom preprocessor"
        case .processor: "Custom processor"
        }
    }

    var toggleLabel: String {
        switch self {
        case .preprocessor: "Run a custom preprocessor"
        case .processor: "Render with a custom processor"
        }
    }

    /// The note under the toggle.
    var settingsNote: String {
        switch self {
        case .preprocessor:
            "Runs a program on every document before it's rendered: the document on standard input, "
                + "Markdown on standard output. Choose a program first."
        case .processor:
            "Renders every document with another program instead of Peep: the Markdown after the "
                + "frontmatter on standard input, HTML on standard output. Peep sanitizes its HTML, and "
                + "Peep's flavors, alerts, wiki links, emoji, and code highlighting don't apply. Choose a "
                + "program first."
        }
    }

    /// The warning's text before the program is turned on; `name` is the program's quoted name.
    func enableWarning(programName name: String) -> String {
        let task =
            switch self {
            case .preprocessor: "on every document you open"
            case .processor: "to render every document you open"
            }
        return "Peep will run \(name) \(task), as you, with access to everything you can access. Each "
            + "document's text is sent to it. Documents can't turn it on or choose another program. Only turn "
            + "this on for a program you trust."
    }

    var openPanelMessage: String {
        switch self {
        case .preprocessor: "Choose the program Peep runs on each document before rendering it."
        case .processor: "Choose the program Peep renders each document with (it reads Markdown and writes HTML)."
        }
    }

    /// The failure bar's title.
    var failureTitle: String {
        switch self {
        case .preprocessor: "Preprocessor failed"
        case .processor: "Processor failed"
        }
    }

    /// What the window shows instead, under the failure bar's title.
    var fallbackNote: String {
        switch self {
        case .preprocessor: "Showing the document without the preprocessor."
        case .processor: "Showing the document as Peep renders it."
        }
    }
}
