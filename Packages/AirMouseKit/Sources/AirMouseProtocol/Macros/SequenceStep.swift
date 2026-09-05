import Foundation

/// One step of a `MacroAction.keySequence`. spec §5.5.1: "`SequenceStep = .combo(modifiers,
/// keyCode, keyLabel) | .text(String ≤ 256)`."
///
/// `Codable`/`Hashable` are compiler-synthesized: an enum with associated values synthesizes to
/// `{"combo": {"modifiers": [...], "keyCode": ..., "keyLabel": ...}}` or `{"text": "..."}` — this
/// *is* the exact JSON shape (spec §5.5.1's "exact JSON shape" requirement), not a strategy layered
/// on top.
public enum SequenceStep: Codable, Hashable, Sendable, Equatable {
    /// A chorded key press, e.g. ⌘C. `keyCode` is a macOS virtual keycode (see
    /// `Keycodes/VirtualKey.swift`); `keyLabel` is the display glyph string captured at record time.
    case combo(modifiers: KeyModifiers, keyCode: UInt16, keyLabel: String)
    /// Literal text to insert (like the `text` control message), ≤ 256 characters
    /// (`ProtocolConstants.macroSequenceStepTextMaxLength`).
    case text(String)
}
