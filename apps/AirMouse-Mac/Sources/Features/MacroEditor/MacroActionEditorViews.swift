// spec §5.5.3 "per-kind fields" — one editor view per `MacroAction` kind, switched on by
// `MacroInspectorView`'s action-kind picker.
import AirMouseProtocol
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct KeyComboActionEditor: View {
    @Binding var draft: MacroDraft

    var body: some View {
        LabeledContent("Shortcut") {
            KeyComboRecorderView(currentGlyph: draft.comboKeyLabel) { modifiers, keyCode, glyph in
                draft.comboModifiers = modifiers
                draft.comboKeyCode = keyCode
                draft.comboKeyLabel = glyph
            }
        }
    }
}

struct KeySequenceActionEditor: View {
    @Binding var draft: MacroDraft
    @State private var isRecordingStepIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(
                "Delay between steps: \(draft.sequenceDelayMs) ms",
                value: $draft.sequenceDelayMs,
                in: ProtocolConstants.macroSequenceInterStepDelayRangeMs,
                step: 50
            )

            List {
                ForEach(Array(draft.sequenceSteps.enumerated()), id: \.offset) { index, step in
                    HStack {
                        Text("\(index + 1).").foregroundStyle(.secondary).monospacedDigit()
                        switch step {
                        case .combo(_, _, let label):
                            Text(label.isEmpty ? "(unset)" : label).monospaced()
                        case .text(let text):
                            Text("“\(text)”").lineLimit(1)
                        }
                        Spacer()
                    }
                }
                .onMove { indices, newOffset in
                    draft.sequenceSteps.move(fromOffsets: indices, toOffset: newOffset)
                }
                .onDelete { indices in
                    draft.sequenceSteps.remove(atOffsets: indices)
                }
            }
            .frame(minHeight: 120, maxHeight: 200)

            HStack {
                KeyComboRecorderView(currentGlyph: "") { modifiers, keyCode, glyph in
                    guard draft.sequenceSteps.count < ProtocolConstants.macroSequenceMaxSteps else { return }
                    draft.sequenceSteps.append(.combo(modifiers: modifiers, keyCode: keyCode, keyLabel: glyph))
                }
                Button("Add Text Step") {
                    guard draft.sequenceSteps.count < ProtocolConstants.macroSequenceMaxSteps else { return }
                    draft.sequenceSteps.append(.text(""))
                }
                Spacer()
                Text("\(draft.sequenceSteps.count)/\(ProtocolConstants.macroSequenceMaxSteps)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            ForEach(Array(draft.sequenceSteps.enumerated()), id: \.offset) { index, step in
                if case .text(let text) = step {
                    TextField(
                        "Text for step \(index + 1)",
                        text: Binding(
                            get: { text },
                            set: { draft.sequenceSteps[index] = .text($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
    }
}

struct LaunchAppActionEditor: View {
    @Binding var draft: MacroDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: draft.bundleID) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 24, height: 24)
                }
                Text(draft.bundleID.isEmpty ? "No app chosen" : draft.bundleID)
                    .foregroundStyle(draft.bundleID.isEmpty ? .secondary : .primary)
                Spacer()
                Button("Choose App…") { chooseApp() }
            }
            Toggle("Bring to front if already running", isOn: $draft.activateIfRunning)
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        // research A9 / spec §5.5.3: "enumerates `/Applications` and `~/Applications` via `NSWorkspace`".
        panel.showsHiddenFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let bundleID = Bundle(url: url)?.bundleIdentifier {
            draft.bundleID = bundleID
        }
    }
}

struct OpenURLActionEditor: View {
    @Binding var draft: MacroDraft

    private var isValid: Bool {
        guard let url = URL(string: draft.urlString), url.scheme != nil else { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("https://example.com", text: $draft.urlString)
                .textFieldStyle(.roundedBorder)
            if !draft.urlString.isEmpty, !isValid {
                Label("Not a valid URL", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
            Text("http, https, file, and any URL scheme with a registered app are allowed (spec §5.5.4).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct RunShortcutActionEditor: View {
    @Binding var draft: MacroDraft
    @State private var availableShortcuts: [String] = []
    @State private var isLoading = false

    var body: some View {
        HStack {
            TextField("Shortcut name", text: $draft.shortcutName)
                .textFieldStyle(.roundedBorder)
            Menu {
                if availableShortcuts.isEmpty {
                    Text(isLoading ? "Loading…" : "No shortcuts found")
                } else {
                    ForEach(availableShortcuts, id: \.self) { name in
                        Button(name) { draft.shortcutName = name }
                    }
                }
            } label: {
                Label("List Shortcuts", systemImage: "list.bullet")
            }
            .task {
                isLoading = true
                availableShortcuts = await ShortcutsCatalog.shared.names()
                isLoading = false
            }
        }
    }
}

struct ScriptActionEditor: View {
    @Binding var draft: MacroDraft
    let allowScriptsGlobal: Bool
    let onOpenSecurityPreferences: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "Script macros run AppleScript/shell you author, and always require confirmation on the phone before they execute (spec §5.5.1).",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
            .font(.footnote)

            if allowScriptsGlobal {
                TextEditor(text: $draft.scriptSource)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                Text("\(draft.scriptSource.utf8.count) bytes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Script macros are disabled. Turn on “Allow script macros” in Preferences › Security to write or edit this macro's source.")
                        .foregroundStyle(.secondary)
                    Button("Open Security Preferences…", action: onOpenSecurityPreferences)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
