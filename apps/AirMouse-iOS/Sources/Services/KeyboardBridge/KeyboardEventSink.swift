// Services/KeyboardBridge/KeyboardEventSink.swift
// The output boundary between the Keyboard feature and the wire (spec §11.1 `key`/`text`/
// `mediaKey` messages). `KeyboardBridge` and `KeyboardViewModel` only ever depend on this
// protocol; the Connection agent implements a real conformance over `ConnectionManager` once it
// exists (per this agent's assignment — this module never imports Network or touches
// `ConnectionManager`).
//
// NOTE for the Connection agent: spec §4.4.4 also requires a standalone `modifiers{flags}`
// message sent immediately on every latch/lock state change (so ⌘-click and menu alternates work
// even before another key is pressed), and §4.4.2's `text` message carries an optional `secure`
// bit (spec §11.1). Neither is expressible through this fixed three-method contract. Until the
// sink grows a `sendModifiers(_:)` (or similar) and a secure flag on `sendText`, modifier-only
// changes are tracked locally for UI only, and `Secure entry` only disables autocorrect/trail
// display on this side — extend this protocol (and `NoOpKeyboardEventSink` /
// `KeyboardBridge`'s call sites) when wiring the real transport.

import Foundation
import AirMouseProtocol

/// spec §4.4.3 (character delivery policy) and §4.4.5 (media keys): everything the Keyboard
/// feature needs to hand off to the wire, expressed without any networking import.
@MainActor
public protocol KeyboardEventSink: AnyObject {
    /// A non-printing key, or any chord carrying ⌘/⌃/⌥ (spec §4.4.3). `virtualKey` is the ANSI
    /// virtual keycode (`VirtualKey.kVK_*`); `char` is the unmodified character if one exists (the
    /// host remaps it to its own layout, spec §5.3.6); `isDown` distinguishes press from release
    /// so the host can auto-repeat (spec §4.4.3: "send `key{down}` on touch-down and `key{up}` on
    /// release so the host auto-repeats").
    func sendKey(virtualKey: UInt16, char: String?, modifiers: KeyModifiers, isDown: Bool)
    /// Printable text with no ⌘/⌃/⌥ modifier — the layout-independent Unicode path (spec §4.4.3,
    /// FR-KB-006).
    func sendText(_ text: String)
    /// A media / system-defined key (spec §4.4.5, §11.1 `mediaKey`).
    func sendMediaKey(_ key: MediaKey)
}

/// Default no-op sink so `KeyboardBridge`/`KeyboardViewModel` are fully usable — including every
/// SwiftUI `#Preview` and this module's own tests — before the Connection agent's real
/// implementation is wired in. Mirrors the `NoOp*` pattern in `App/DefaultServices.swift`.
@MainActor
public final class NoOpKeyboardEventSink: KeyboardEventSink {
    public init() {}

    public func sendKey(virtualKey: UInt16, char: String?, modifiers: KeyModifiers, isDown: Bool) {
        Log.app.notice("NoOpKeyboardEventSink.sendKey — no Connection agent wired yet")
    }

    public func sendText(_ text: String) {
        // Never log `text` itself — spec §7 / CLAUDE.md: never log keys, secrets, or typed text.
        Log.app.notice("NoOpKeyboardEventSink.sendText — no Connection agent wired yet")
    }

    public func sendMediaKey(_ key: MediaKey) {
        Log.app.notice("NoOpKeyboardEventSink.sendMediaKey — no Connection agent wired yet")
    }
}
