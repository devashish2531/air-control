// Services/KeyboardBridge/ModifierLatchState.swift
// Pure, dependency-free state machine for the modifier row's latch/lock semantics (spec §4.4.4):
// "off → latched (single tap) → off after the next key or click" and "off → locked (double tap
// within 300 ms) → off (tap)". Deliberately has no UIKit/SwiftUI dependency — only `Duration`/
// `ContinuousClock.Instant` (both plain Swift stdlib types) so `now` is fully injectable and this
// type is trivially unit-testable (`Tests/ModifierLatchStateTests.swift`).

import AirControlProtocol

/// The five modifier-row keys that participate in latch/lock (spec §4.4.4). Caps Lock
/// intentionally has no case here: spec calls it out as always a *locked* ⇧ flag with no latch
/// state of its own (FR-KB-012) — `KeyboardBridge`/`KeyboardViewModel` track it as a separate
/// plain boolean, toggled directly by a single tap.
public enum ModifierKey: String, CaseIterable, Sendable, Hashable {
    case command
    case option
    case control
    case shift
    case function

    /// The wire `KeyModifiers` flag this key contributes while latched or locked.
    public var wireFlag: KeyModifiers {
        switch self {
        case .command: .command
        case .option: .option
        case .control: .control
        case .shift: .shift
        case .function: .function
        }
    }
}

/// Latch/lock state for every `ModifierKey`, plus the union of active wire flags.
public struct ModifierLatchState: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case off
        case latched
        case locked
    }

    /// spec §4.4.4 "double tap within 300 ms"; matches the `doubleTapInterval` constant (§11.3).
    public static let doubleTapWindow: Duration = .milliseconds(300)

    private var states: [ModifierKey: State] = [:]
    private var lastTapAt: [ModifierKey: ContinuousClock.Instant] = [:]

    public init() {}

    public func state(for key: ModifierKey) -> State {
        states[key] ?? .off
    }

    /// Registers a tap on `key`'s modifier button at `now` and returns the resulting state:
    /// - `.off` → `.latched`.
    /// - `.latched` → `.locked` if this tap lands within `doubleTapWindow` of the previous one,
    ///   else back to `.off` (a slow second tap cancels the latch rather than re-arming it).
    /// - `.locked` → `.off` (spec §4.4.4's "locked … off (tap)").
    @discardableResult
    public mutating func tap(_ key: ModifierKey, at now: ContinuousClock.Instant) -> State {
        let current = state(for: key)
        let next: State
        switch current {
        case .off:
            next = .latched
        case .latched:
            if let last = lastTapAt[key], now - last <= Self.doubleTapWindow {
                next = .locked
            } else {
                next = .off
            }
        case .locked:
            next = .off
        }
        states[key] = next
        lastTapAt[key] = now
        return next
    }

    /// Call once a non-modifier key/click has been sent downstream: every currently-`.latched`
    /// modifier is single-use and clears now; `.locked` modifiers persist (spec §4.4.4).
    public mutating func consumeLatchesAfterKey() {
        for key in ModifierKey.allCases where states[key] == .latched {
            states[key] = .off
        }
    }

    /// Clears every modifier back to `.off` (e.g. leaving the Keyboard tab, toggling Secure entry).
    public mutating func clear() {
        states.removeAll()
    }

    /// The union of wire flags for every key currently latched or locked (spec §4.4.4: "the flags
    /// are also attached to `click`/`key` messages").
    public var activeFlags: KeyModifiers {
        var flags: KeyModifiers = []
        for key in ModifierKey.allCases where state(for: key) != .off {
            flags.insert(key.wireFlag)
        }
        return flags
    }
}
