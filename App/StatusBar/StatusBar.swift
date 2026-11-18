import SwiftUI

/// The strip along the bottom of a document window: quick facts about the document, leading,
/// and window toggles (pin, outline), trailing. Toggled with View > Show/Hide Status Bar.
///
/// Painted with the window's theme background (`WindowChrome`), under a border in the theme's
/// border color, so it blends with the page; its text and controls use the scheme that contrasts
/// with that background.
struct StatusBar: View {
    let document: MarkdownDocument
    let model: StatusBarModel
    let chrome: WindowChrome
    let toggleOutline: () -> Void
    let togglePinned: () -> Void
    let scrollToNextChange: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = chrome.colors(in: colorScheme)
        VStack(spacing: 0) {
            ChromeBorder(chrome: chrome)
            HStack(spacing: 12) {
                WordCountItem(count: document.content?.page.wordCount)
                if let changes = model.offScreenChanges {
                    ChangesItem(changes: changes, scrollToNext: scrollToNextChange)
                }
                Spacer(minLength: 0)
                PinToggleItem(isPinned: model.isPinned, toggle: togglePinned)
                OutlineToggleItem(isOutlineVisible: model.isOutlineVisible, toggle: toggleOutline)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .environment(\.colorScheme, colors.contentScheme)
        }
        .background(Color(colors.background))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("status-bar")
    }
}

/// Shows or hides the outline sidebar, like View > Show/Hide Outline; tinted while it is shown.
struct OutlineToggleItem: View {
    let isOutlineVisible: Bool
    let toggle: () -> Void

    var body: some View {
        let title = isOutlineVisible ? "Hide Outline" : "Show Outline"
        Button(action: toggle) {
            Image(systemName: "list.bullet")
                .foregroundStyle(isOutlineVisible ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier("outline-toggle")
    }
}

/// Pins or unpins the window (and its tabs), like Window > Pin/Unpin Window; filled and tinted
/// while pinned.
struct PinToggleItem: View {
    let isPinned: Bool
    let toggle: () -> Void

    var body: some View {
        let title = isPinned ? "Unpin Window" : "Pin Window"
        Button(action: toggle) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .foregroundStyle(isPinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(isPinned ? "on" : "off")
        .accessibilityIdentifier("pin-toggle")
    }
}

/// Change marks out of view after a live reload: "Changed ↓ (2)", pointing at the next one
/// (below first, as clicking scrolls); clicking scrolls to it.
struct ChangesItem: View {
    let changes: OffScreenChanges
    let scrollToNext: () -> Void

    var body: some View {
        let arrow = changes.below > 0 ? "arrow.down" : "arrow.up"
        Button(action: scrollToNext) {
            HStack(spacing: 3) {
                Text("Changed")
                Image(systemName: arrow)
                Text("(\(changes.total.formatted()))").monospacedDigit()
            }
            .foregroundStyle(.tint)
        }
        .buttonStyle(.borderless)
        .help("Scroll to the next change")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.label(for: changes))
        .accessibilityHint("Scrolls to the next change")
        .accessibilityIdentifier("changes-item")
    }

    /// "2 changes below", "1 change above", "3 changes out of view".
    static func label(for changes: OffScreenChanges) -> String {
        let noun = changes.total == 1 ? "change" : "changes"
        let place =
            switch (changes.above > 0, changes.below > 0) {
            case (true, true): "out of view"
            case (true, false): "above"
            default: "below"
            }
        return "\(changes.total.formatted()) \(noun) \(place)"
    }
}

/// The document's word count (`RenderedPage.wordCount`); empty until the first render lands.
struct WordCountItem: View {
    let count: Int?

    var body: some View {
        if let count {
            let text = Self.text(for: count)
            Text(text)
                .monospacedDigit()
                .accessibilityIdentifier("word-count")
                .accessibilityLabel(text)
        }
    }

    /// "1 word", "1,340 words" (grouped for the reader's locale).
    static func text(for count: Int) -> String {
        count == 1 ? "1 word" : "\(count.formatted()) words"
    }
}
