import PeepCore
import SwiftUI

/// Settings > Programs > Custom preprocessor (#57) and Custom processor (#106)
/// (`ProgramsSettingsView`), one per `model.kind`: the on/off toggle (behind a warning), the program (chosen
/// with an Open panel, never typed), its arguments as a list, the last run in this session, and
/// Reset. Identifiers (`settings-custom-preprocessor*`, `settings-custom-processor*`) are for UI
/// tests.
struct CustomProgramSection: View {
    @Bindable var model: CustomProgramModel

    var body: some View {
        Section(model.kind.sectionTitle) {
            Toggle(
                model.kind.toggleLabel,
                isOn: Binding(get: { model.isEnabled }, set: { model.setEnabled($0) })
            )
            .disabled(model.executablePath == nil)
            .accessibilityIdentifier(identifierPrefix)
            note(model.kind.settingsNote)

            LabeledContent("Program:") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: model.executablePath ?? "None")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(model.executablePath == nil ? .secondary : .primary)
                            .help(model.executablePath ?? "")
                            .accessibilityIdentifier("\(identifierPrefix)-path")
                        Button("Choose…") {
                            Task { await model.chooseExecutable() }
                        }
                        .accessibilityIdentifier("\(identifierPrefix)-choose")
                    }
                    if let problem = model.rejectedChoice ?? model.executableProblem {
                        Text(verbatim: problem)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("\(identifierPrefix)-problem")
                    }
                }
            }

            LabeledContent("Arguments:") {
                ArgumentListEditor(
                    arguments: model.arguments, commit: model.setArguments, identifierPrefix: identifierPrefix)
            }

            LabeledContent("Last run:") {
                Text(verbatim: lastRunText)
                    .foregroundStyle(model.lastRun?.error == nil ? .secondary : .primary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("\(identifierPrefix)-last-run")
            }

            Button("Reset") {
                model.reset()
            }
            .disabled(model.executablePath == nil && model.arguments.isEmpty && !model.isEnabled)
            .accessibilityIdentifier("\(identifierPrefix)-reset")
        }
        .alert("Run a program on every document?", isPresented: $model.isConfirmingEnable) {
            Button("Turn On") { model.confirmEnable() }
                .accessibilityIdentifier("\(identifierPrefix)-confirm")
            Button("Cancel", role: .cancel) { model.cancelEnable() }
        } message: {
            Text(verbatim: warning)
        }
    }

    /// `settings-custom-preprocessor`, `settings-custom-processor`.
    private var identifierPrefix: String {
        "settings-custom-\(model.kind.noun)"
    }

    /// The warning before turning the program on.
    private var warning: String {
        model.kind.enableWarning(programName: model.executableName.map { "“\($0)”" } ?? "the program")
    }

    private var lastRunText: String {
        guard let run = model.lastRun else {
            return "None yet."
        }
        let time = run.date.formatted(date: .omitted, time: .standard)
        guard let error = run.error else {
            return "Succeeded on \(run.documentName) at \(time)."
        }
        return "Failed on \(run.documentName) at \(time): \(error.message)"
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A custom program's arguments, one field each, passed verbatim (no shell, no splitting).
/// Edits are committed on Return and when a field loses focus, so a half-typed argument
/// doesn't re-render every open document on each keystroke; empty fields are dropped.
private struct ArgumentListEditor: View {
    let arguments: [String]
    let commit: ([String]) -> Void
    let identifierPrefix: String

    private struct Row: Identifiable {
        let id = UUID()
        var text: String
    }

    @State private var rows: [Row] = []
    @FocusState private var focusedRow: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach($rows) { $row in
                let index = rows.firstIndex { $0.id == row.id } ?? 0
                HStack(spacing: 4) {
                    TextField("Argument \(index + 1)", text: $row.text)
                        .labelsHidden()
                        .font(.system(.body, design: .monospaced))
                        .focused($focusedRow, equals: row.id)
                        .onSubmit(commitRows)
                        .accessibilityIdentifier("\(identifierPrefix)-argument-\(index + 1)")
                    Button {
                        rows.removeAll { $0.id == row.id }
                        commitRows()
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this argument")
                    .accessibilityLabel("Remove argument \(index + 1)")
                }
            }
            Button("Add Argument") {
                let row = Row(text: "")
                rows.append(row)
                focusedRow = row.id
            }
            .accessibilityIdentifier("\(identifierPrefix)-add-argument")
        }
        .onAppear { rows = arguments.map { Row(text: $0) } }
        .onChange(of: arguments) { _, newValue in
            // A change from elsewhere (Reset); the editor's own commits already match.
            if CustomProgramModel.committed(rows.map(\.text)) != newValue {
                rows = newValue.map { Row(text: $0) }
            }
        }
        .onChange(of: focusedRow) { commitRows() }
        .onDisappear(perform: commitRows)
    }

    private func commitRows() {
        commit(rows.map(\.text))
    }
}
