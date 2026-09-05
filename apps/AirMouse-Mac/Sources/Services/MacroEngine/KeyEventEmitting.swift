// Minimal protocol slot for `EventInjector` (arch §3.3), which this module does not own (CLAUDE.md:
// "write a minimal protocol in your own module ... if you need a type owned by another module that
// does not exist yet"). `MacroEngine`'s `keyCombo`/`keySequence` action kinds forward to it (spec
// §5.5.4: "`EventInjector` tap with flags (same path as `key`)"); the injection agent's real
// `EventInjector` actor should conform to this from its own module, then be passed into
// `MacroFeature.make(environment:keyEmitter:)` in place of `NullKeyEventEmitter`.
import AirMouseProtocol

/// Everything a macro action needs from the injection layer: a chorded key press/release and a literal
/// text insert (spec §5.5.4 keyCombo/keySequence `.text` steps — same wire shape as the `text` control
/// message). Deliberately excludes clicks, scrolling, and modifiers-only events — no macro action kind
/// needs them (`MacroAction`, `AirMouseProtocol/Macros/MacroAction.swift`).
public protocol KeyEventEmitting: Sendable {
    /// Presses and releases `virtualKey` with `modifiers` held for the duration of the down/up pair
    /// (spec §5.3.6 keyboard injection path). `virtualKey` is a macOS virtual keycode
    /// (`AirMouseProtocol.VirtualKey`); `modifiers` is the canonical `KeyModifiers` option set.
    func press(virtualKey: UInt16, modifiers: KeyModifiers) async
    /// Inserts literal text via the same pacer/queue the `text` control message uses.
    func typeText(_ text: String) async
}

/// No-op `KeyEventEmitting` used before the injection agent's real `EventInjector` conforms and is
/// wired in via `MacroFeature.make`. Lets this module, its tests, and the editor's "Test" button build
/// and run standalone; every call is a documented, harmless no-op rather than a crash.
public struct NullKeyEventEmitter: KeyEventEmitting {
    public init() {}
    public func press(virtualKey: UInt16, modifiers: KeyModifiers) async {}
    public func typeText(_ text: String) async {}
}
