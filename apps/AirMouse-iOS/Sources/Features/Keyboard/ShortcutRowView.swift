// Features/Keyboard/ShortcutRowView.swift
// Common shortcuts row (this agent's assignment: "⌘Space, ⌘Tab, ⌘C/V, ⌘Z, ⌘Q, screenshot") plus
// an editor sheet for spec §4.4.5/FR-KB-008's "user-editable (add/remove/reorder, stored in
// UserDefaults)" requirement, covering the full default chord list.

import SwiftUI

struct ShortcutRowView: View {
    let viewModel: KeyboardViewModel
    @State private var showEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Shortcuts", comment: "Keyboard screen: shortcut row section header")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showEditor = true
                } label: {
                    Text("Edit", comment: "Keyboard screen: edit shortcuts button")
                }
                .minimumTapTarget()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.shortcutRow) { chord in
                        Button {
                            viewModel.fireShortcut(chord)
                        } label: {
                            Text(chord.label)
                                .font(.callout.monospaced())
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibleButton(label: LocalizedStringKey(chord.accessibilityLabel))
                    }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                ShortcutEditorView(viewModel: viewModel)
            }
        }
    }
}

private struct ShortcutEditorView: View {
    let viewModel: KeyboardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(viewModel.shortcutRow) { chord in
                    Label(chord.label, systemImage: "command")
                        .accessibilityLabel(chord.accessibilityLabel)
                }
                .onDelete { indices in
                    viewModel.shortcutRow.remove(atOffsets: indices)
                }
                .onMove { indices, newOffset in
                    viewModel.shortcutRow.move(fromOffsets: indices, toOffset: newOffset)
                }
            } header: {
                Text("On the row", comment: "Shortcut editor: currently shown shortcuts section header")
            }
            Section {
                ForEach(ShortcutChord.allCases.filter { !viewModel.shortcutRow.contains($0) }) { chord in
                    Button {
                        viewModel.shortcutRow.append(chord)
                    } label: {
                        Label(chord.label, systemImage: "plus.circle")
                    }
                    .accessibilityLabel(chord.accessibilityLabel)
                }
            } header: {
                Text("Add", comment: "Shortcut editor: available-to-add shortcuts section header")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(Text("Shortcuts", comment: "Shortcut editor navigation title"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    dismiss()
                } label: {
                    Text("Done", comment: "Shortcut editor: done button")
                }
            }
        }
    }
}
