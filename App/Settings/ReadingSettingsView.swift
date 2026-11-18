import SwiftUI

/// Settings > Reading: how open documents behave while you read them. "Highlight changes when a
/// file is saved" reads `SettingsModel` and changes the setting through
/// `setHighlightsChanges(_:)`; the identifier (`settings-highlight-changes`) is for UI tests.
struct ReadingSettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Highlight changes when a file is saved",
                    isOn: Binding(get: { model.highlightsChanges }, set: model.setHighlightsChanges)
                )
                .accessibilityIdentifier("settings-highlight-changes")
                note(
                    "After a document’s file changes, a bar beside each changed block fades out once "
                        + "you’ve seen it. Changes out of view are counted in the status bar; click the count "
                        + "to go to the next one.")
            }
        }
        .formStyle(.columns)
        .padding(20)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Secondary text under a control.
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
