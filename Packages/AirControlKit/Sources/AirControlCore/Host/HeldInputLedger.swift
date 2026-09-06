import Foundation
import AirControlProtocol

/// One held (down-but-not-yet-up) input the host must remember to release (spec §5.3.11:
/// "`releaseAll()` must undo" — mouse buttons, modifier keys, and ordinary keys held via
/// `action: down`).
public struct HeldInputItem: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case mouseButton(MouseButton)
        /// A modifier key, held via `flagsChanged` (identified by its macOS virtual keycode).
        case modifierKey(UInt16)
        /// An ordinary key held via `key { action: down }` (identified by its virtual keycode).
        case key(Int)
    }

    public var kind: Kind

    public init(_ kind: Kind) {
        self.kind = kind
    }
}

/// Tracks every input currently "held" for one session — buttons down, modifiers held, keys held
/// — so a caller can release all of them at once: on the 2 s no-heartbeat stale transition (spec
/// §3.4.6 / §5.3.11: "release all held buttons/modifiers/keys"), and as a 60 s watchdog safety net
/// even while heartbeats continue (spec §5.3.11, §11.3: "Held-input watchdog | 60 s").
///
/// A pure value type (arch §3.1): the owning `HostSession` actor holds one `var` per connection
/// and supplies `now` explicitly, same as every other kit state machine.
public struct HeldInputLedger: Sendable, Equatable {
    /// Monotonic "held since" timestamp (seconds) per item.
    private var heldSince: [HeldInputItem: TimeInterval] = [:]

    public init() {}

    /// Records that `item` went down at `now`. Re-recording an already-held item (e.g. a repeat)
    /// does *not* reset its watchdog clock — the watchdog measures continuous hold duration since
    /// the item first went down, matching "held for 60 s" rather than "idle for 60 s".
    public mutating func recordDown(_ item: HeldInputItem, now: TimeInterval) {
        if heldSince[item] == nil {
            heldSince[item] = now
        }
    }

    /// Records that `item` went up; a no-op if it wasn't held.
    public mutating func recordUp(_ item: HeldInputItem) {
        heldSince.removeValue(forKey: item)
    }

    public var heldItems: [HeldInputItem] { Array(heldSince.keys) }
    public var isEmpty: Bool { heldSince.isEmpty }
    public var count: Int { heldSince.count }

    public func isHeld(_ item: HeldInputItem) -> Bool {
        heldSince[item] != nil
    }

    /// Items that have been continuously held for ≥ 60 s (spec §11.3's watchdog), as of `now`.
    public func itemsExceedingWatchdog(now: TimeInterval) -> [HeldInputItem] {
        let threshold = TimeInterval(ProtocolConstants.heldInputWatchdogSeconds)
        return heldSince.compactMap { item, since in now - since >= threshold ? item : nil }
    }

    /// Clears and returns every held item (the caller then posts the corresponding "up"/
    /// `flagsChanged` events to `EventInjector`, spec §5.3.11) — used on stale/close/watchdog.
    @discardableResult
    public mutating func releaseAll() -> [HeldInputItem] {
        let items = heldItems
        heldSince.removeAll()
        return items
    }

    /// Clears only the given items (e.g. after a watchdog trip releases some but not all).
    public mutating func release(_ items: [HeldInputItem]) {
        for item in items { heldSince.removeValue(forKey: item) }
    }
}
