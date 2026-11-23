import SwiftUI

/// Settings > Programs: the custom preprocessor (#57) and custom processor (#106), a
/// `CustomProgramSection` each, in pipeline order. They were Settings > Markdown's last sections
/// until that pane outgrew small screens (and CI's, whose Dock covered them). Like Settings >
/// Markdown, a change applies to open documents at once.
struct ProgramsSettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            CustomProgramSection(model: model.customPreprocessor)
            CustomProgramSection(model: model.customProcessor)
        }
        .formStyle(.columns)
        .padding(20)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
