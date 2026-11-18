import SwiftUI

/// Settings > Reading: how open documents behave while you read them. "Highlight changes when a
/// file is saved" and its supplemental "Scroll to the first change" (disabled while highlights
/// are off) read `SettingsModel` and change the settings through `setHighlightsChanges(_:)` and
/// `setScrollsToChanges(_:)`; the identifiers (`settings-highlight-changes`,
/// `settings-scroll-to-changes`) are for UI tests.
struct ReadingSettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Highlight changes when a file is saved",
                    isOn: binding(\.highlightsChanges, model.setHighlightsChanges)
                )
                .accessibilityIdentifier("settings-highlight-changes")
                note(
                    "After a document’s file changes, a bar beside each changed block fades out once "
                        + "you’ve seen it. Changes out of view are counted in the status bar; click the count "
                        + "to go to the next one.")
                Toggle(
                    "Scroll to the first change",
                    isOn: binding(\.scrollsToChanges, model.setScrollsToChanges)
                )
                .accessibilityIdentifier("settings-scroll-to-changes")
                .disabled(!model.highlightsChanges)
                .padding(.leading, 20)
                note("When no change is in view after a save, scroll to the first one.")
                    .padding(.leading, 20)
            }
        }
        .formStyle(.columns)
        .padding(20)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A binding that reads the model's property and changes it through `set`.
    private func binding<Value>(
        _ keyPath: KeyPath<SettingsModel, Value>, _ set: @escaping (Value) -> Void
    ) -> Binding<Value> {
        Binding(get: { model[keyPath: keyPath] }, set: set)
    }

    /// Secondary text under a control.
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
