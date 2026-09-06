// spec §5.5.3 "Inspector for the selected macro". One `Form` covering the fields common to every kind
// plus the per-kind editor from `MacroActionEditorViews.swift`.
import AirControlProtocol
import SwiftUI

struct MacroInspectorView: View {
    @Binding var draft: MacroDraft
    let allowScriptsGlobal: Bool
    let isNew: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    let onTest: () -> Void
    let onOpenSecurityPreferences: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Appearance") {
                    TextField("Name", text: $draft.name)
                        .onChange(of: draft.name) { _, newValue in
                            if newValue.count > ProtocolConstants.macroNameMaxLength {
                                draft.name = String(newValue.prefix(ProtocolConstants.macroNameMaxLength))
                            }
                        }
                    SFSymbolPicker(symbolName: $draft.icon)
                    Picker("Tint", selection: $draft.tint) {
                        Text("None").tag(MacroTint?.none)
                        ForEach(MacroTint.allCases, id: \.self) { tint in
                            Label(tint.rawValue.capitalized, systemImage: "circle.fill")
                                .foregroundStyle(tint.swiftUIColor)
                                .tag(MacroTint?.some(tint))
                        }
                    }
                    Toggle("Show on media page", isOn: $draft.showOnMediaPage)
                }

                Section("Behavior") {
                    Toggle("Requires confirmation", isOn: $draft.requiresConfirmationOverride)
                        .disabled(draft.kind.isScript)
                        .help(draft.kind.isScript ? "Script macros always require confirmation (spec §5.5.1)." : "")
                }

                Section("Action") {
                    Picker("Kind", selection: $draft.kind) {
                        ForEach(MacroDraft.ActionKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)

                    switch draft.kind {
                    case .keyCombo:
                        KeyComboActionEditor(draft: $draft)
                    case .keySequence:
                        KeySequenceActionEditor(draft: $draft)
                    case .launchApp:
                        LaunchAppActionEditor(draft: $draft)
                    case .openURL:
                        OpenURLActionEditor(draft: $draft)
                    case .runShortcut:
                        RunShortcutActionEditor(draft: $draft)
                    case .appleScript, .shellCommand:
                        ScriptActionEditor(
                            draft: $draft,
                            allowScriptsGlobal: allowScriptsGlobal,
                            onOpenSecurityPreferences: onOpenSecurityPreferences
                        )
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Test", action: onTest)
                    .disabled(draft.makeAction() == nil)
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button(isNew ? "Add" : "Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.isEmpty || draft.makeAction() == nil)
            }
            .padding()
        }
        .frame(minWidth: 460, minHeight: 520)
    }
}

extension MacroTint {
    var swiftUIColor: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .gray: .gray
        }
    }
}
