// Features/Keyboard/KeyboardAccessoryBar.swift
// docs/08 §3.2 — the Keyboard tab's software-keyboard input accessory: a tab strip (so switching
// tabs while the keyboard is up doesn't require dismissing it first, docs/08 §2.2) plus a gear
// shortcut into Settings and a trailing Done to hide the keyboard. Hosted inside a `UIInputView`
// via `UIHostingController` by `KeyInputHostRepresentable`'s coordinator (see that file and
// `Services/KeyboardBridge/KeyInputHostView.swift`'s headers) — this type has no UIKit dependency
// of its own, and the current tab is always `.keyboard` since this bar only ever shows while the
// Keyboard tab's hidden host view is first responder.

import SwiftUI

struct KeyboardAccessoryBar: View {
    let currentTab: AppTab
    let onSelectTab: (AppTab) -> Void
    let onOpenSettings: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
            gearButton
            Spacer(minLength: 8)
            doneButton
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(.bar)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            onSelectTab(tab)
        } label: {
            Image(systemName: tab.systemImage)
                .font(.body)
                .foregroundStyle(tab == currentTab ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibleButton(label: LocalizedStringKey(tab.title))
        .accessibleLatched(tab == currentTab)
    }

    private var gearButton: some View {
        Button(action: onOpenSettings) {
            Image(systemName: "gearshape")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibleButton(label: LocalizedStringKey("Settings"))
    }

    private var doneButton: some View {
        Button(action: onDone) {
            Text("Done", comment: "Keyboard accessory bar: hides the software keyboard")
                .fontWeight(.semibold)
        }
        .buttonStyle(.plain)
        .minimumTapTarget()
        .accessibleButton(label: LocalizedStringKey("Hide keyboard"))
    }
}

#Preview {
    KeyboardAccessoryBar(currentTab: .keyboard, onSelectTab: { _ in }, onOpenSettings: {}, onDone: {})
}
