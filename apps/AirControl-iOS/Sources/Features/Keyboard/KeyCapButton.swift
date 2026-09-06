// Features/Keyboard/KeyCapButton.swift
// Shared key-cap visual style for every button on the Keyboard screen (docs/08 §3.1: "Keys: 44 pt
// tall, 8 pt spacing, RoundedRectangle(cornerRadius: 10, style: .continuous), fill
// Color(.secondarySystemBackground), pressed .tertiarySystemBackground, latched modifiers
// .tint.opacity(0.2) fill with .tint glyph. Same in light and dark."). Semantic system colors
// only — no literal black/white/grey — so every key reads correctly in both themes (docs/08 §1
// problem 4). Used by `ExtendedKeyBarView`, `ModifierBarView`, `MediaKeyBarView`, and
// `ShortcutRowView` so the whole tab shares one visual language.

import SwiftUI

/// Visual states a key cap can be in: `.normal` (idle), `.pressed` (finger down, no latch
/// semantics), `.latched`/`.locked` (modifier-style toggle state, tinted per docs/08 §3.1). Locked
/// keeps the same fill as latched — the lock glyph/underline overlay is what distinguishes the two
/// (colour is never the sole signal, spec §4.8.1.5).
enum KeyCapState: Equatable {
    case normal
    case pressed
    case latched
    case locked
}

private struct KeyCapModifier: ViewModifier {
    let state: KeyCapState

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isTinted ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fillStyle)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var isTinted: Bool {
        state == .latched || state == .locked
    }

    private var fillStyle: AnyShapeStyle {
        switch state {
        case .normal: AnyShapeStyle(Color(.secondarySystemBackground))
        case .pressed: AnyShapeStyle(Color(.tertiarySystemBackground))
        case .latched, .locked: AnyShapeStyle(.tint.opacity(0.2))
        }
    }
}

extension View {
    /// Applies the shared key-cap shape/fill/glyph-tint for `state` (docs/08 §3.1).
    func keyCapStyle(_ state: KeyCapState) -> some View {
        modifier(KeyCapModifier(state: state))
    }
}
