import PeepCore
import SwiftUI

/// Settings > Quick Look: how Finder's Quick Look previews look. The theme picker reads
/// `SettingsModel` and changes the setting through `setQuickLookTheme(id:)`; the identifier
/// (`settings-quick-look-theme`) is for UI tests. The app publishes it to the preview extension
/// (`QuickLookConfigurationPublisher`), so it changes no window.
struct QuickLookSettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("Quick Look theme:", selection: binding(\.quickLookThemeID, model.setQuickLookTheme(id:))) {
                    Text("Same as default theme").tag(SettingsModel.quickLookFollowsDefault)
                    ForEach(Array(model.themeSections.enumerated()), id: \.offset) { _, section in
                        Divider()
                        ForEach(section, id: \.id) { theme in
                            Text(theme.displayName).tag(theme.id)
                        }
                    }
                }
                .accessibilityIdentifier("settings-quick-look-theme")
                note("Previews in Finder and Quick Look use this theme. A document’s peep.theme still wins.")
            }

            Section {
                note(
                    "Settings > Markdown applies to previews too. Images next to the file and custom "
                        + "programs never do: Quick Look shows the document alone.")
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
