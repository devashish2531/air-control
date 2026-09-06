// Features/Keyboard/ModifierBarView.swift
// Modifier row (spec §4.1.6 "⌘ ⌥ ⌃ ⇧ fn Caps") with latch/lock visuals (spec §4.4.4: "Latched:
// filled background + underline; locked: filled + underline + small lock glyph (never colour
// alone, NFR-A11Y-004)"), styled per docs/08 §3.1's shared key-cap look (`keyCapStyle`, this
// module's `KeyCapButton.swift`). Every button meets the 44 pt minimum tap target (spec §4.8) and
// carries an accessibility label + a spoken "Off"/"Latched"/"Locked" value so the state reaches
// VoiceOver users without relying on colour.

import SwiftUI
import AirControlProtocol

struct ModifierBarView: View {
    let viewModel: KeyboardViewModel

    var body: some View {
        AdaptiveKeyRow(spacing: 8) {
            ForEach(ModifierKey.allCases, id: \.self) { key in
                ModifierKeyButton(
                    symbolName: symbolName(for: key),
                    label: label(for: key),
                    state: viewModel.modifierState(key),
                    action: { viewModel.tapModifier(key) }
                )
            }
            ModifierKeyButton(
                symbolName: "capslock",
                label: String(localized: "Caps Lock", comment: "Keyboard modifier row: Caps Lock button accessibility label"),
                state: viewModel.isCapsLockOn ? .locked : .off,
                action: { viewModel.tapCapsLock() }
            )
        }
        .accessibilityElement(children: .contain)
    }

    private func symbolName(for key: ModifierKey) -> String {
        switch key {
        case .command: "command"
        case .option: "option"
        case .control: "control"
        case .shift: "shift"
        case .function: "fn"
        }
    }

    private func label(for key: ModifierKey) -> String {
        switch key {
        case .command: String(localized: "Command", comment: "Keyboard modifier row: Command key accessibility label")
        case .option: String(localized: "Option", comment: "Keyboard modifier row: Option key accessibility label")
        case .control: String(localized: "Control", comment: "Keyboard modifier row: Control key accessibility label")
        case .shift: String(localized: "Shift", comment: "Keyboard modifier row: Shift key accessibility label")
        case .function: String(localized: "Function", comment: "Keyboard modifier row: fn key accessibility label")
        }
    }
}

private struct ModifierKeyButton: View {
    let symbolName: String
    let label: String
    let state: ModifierLatchState.State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.title3)
                .frame(minWidth: 44, minHeight: 44)
                .keyCapStyle(keyCapState)
                .overlay(alignment: .bottom) {
                    if state != .off {
                        Rectangle()
                            .fill(.tint)
                            .frame(height: 2)
                            .padding(.horizontal, 8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if state == .locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tint)
                            .padding(3)
                    }
                }
        }
        // Without an explicit style, `Button`'s default chrome tints icon-only labels with
        // `.tint` regardless of the label's own `.foregroundStyle` — that silently overrode
        // `keyCapStyle`'s `.primary` for the off state, showing every modifier glyph blue
        // (docs/08 §3.1: colour is state, not chrome).
        .buttonStyle(.plain)
        .minimumTapTarget()
        .accessibleButton(label: LocalizedStringKey(label))
        .accessibleLatched(state != .off)
        .accessibilityValue(accessibilityValueText)
    }

    private var keyCapState: KeyCapState {
        switch state {
        case .off: .normal
        case .latched: .latched
        case .locked: .locked
        }
    }

    private var accessibilityValueText: String {
        switch state {
        case .off: String(localized: "Off", comment: "Keyboard modifier key accessibility value")
        case .latched: String(localized: "Latched", comment: "Keyboard modifier key accessibility value")
        case .locked: String(localized: "Locked", comment: "Keyboard modifier key accessibility value")
        }
    }
}
