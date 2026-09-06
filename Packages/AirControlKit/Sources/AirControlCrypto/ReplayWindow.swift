/// RFC 6479-style sliding-window replay protection for one (sessionID, direction) pair
/// (spec §3.5.4):
///
/// ```
/// if counter > highest:            shift bitmap left by (counter − highest) (saturating), set bit0,
///                                   highest = counter, accept
/// elif highest − counter ≥ 64:     drop (too old)
/// elif bitmap bit (highest − counter) set: drop (replay)
/// else:                            set bit, accept
/// ```
///
/// This check runs **after** AEAD authentication succeeds (spec §3.5.4: "The check runs after AEAD
/// authentication succeeds (an attacker must not be able to poison the window)") — `MotionCrypto` does
/// not call into this type itself; the caller (host session logic, owned by `AirControlCore`) opens the
/// datagram first and only then calls `accept(_:)`.
///
/// Deliberately does *not* implement the separate 8-datagram "application-level staleness" rule
/// (spec §3.5.4, §11.3: "stale-apply window ... 8") — that is a distinct policy question ("should this
/// already-authenticated, already-non-replayed datagram's deltas be applied to the pointer"), exposed
/// here as the standalone `ReplayWindow.isStaleToApply(counter:highestApplied:)` helper so callers don't
/// confuse the two windows.
public struct ReplayWindow: Sendable, Equatable {
    /// Window width in datagrams (spec §3.5.4, §11.3: "Replay window ... 64").
    // TODO(integration): move to ProtocolConstants.
    public static let size: UInt64 = 64

    /// Threshold, in datagrams behind the highest *applied* counter, beyond which an accepted datagram's
    /// deltas must not be applied to the pointer (spec §3.5.4, §11.3: "stale-apply window ... 8").
    // TODO(integration): move to ProtocolConstants.
    public static let staleApplyThreshold: UInt64 = 8

    /// The result of feeding one counter through the window.
    public enum Decision: Sendable, Equatable {
        /// Accepted: either a new high-water mark, or an in-window counter not previously seen.
        case accepted
        /// Rejected: this exact counter (or an equally-old one already covered by the window) was
        /// already accepted.
        case rejectedReplay
        /// Rejected: this counter is more than `size` behind the current high-water mark and can no
        /// longer be represented by the window.
        case rejectedTooOld
    }

    /// Highest counter accepted so far.
    public private(set) var highest: UInt64

    /// Bit `i` set means "the datagram at `highest - i` has been accepted". Bit 0 always mirrors the
    /// most-recently-accepted counter, which is `highest` after any accept.
    public private(set) var bitmap: UInt64

    /// Starts a fresh window. The default (`highest: 0, bitmap: 0`) is the state before any datagram for
    /// this (sessionID, direction) pair has ever been accepted, so that the very first datagram (which
    /// legitimately has `counter == 0`, spec §3.5.1: "counter ... starts at 0") is accepted rather than
    /// rejected as a self-duplicate.
    public init(highest: UInt64 = 0, bitmap: UInt64 = 0) {
        self.highest = highest
        self.bitmap = bitmap
    }

    /// Feeds `counter` through the window, mutating state on `.accepted` and leaving state untouched on
    /// either rejection.
    @discardableResult
    public mutating func accept(_ counter: UInt64) -> Decision {
        if counter > highest {
            let shift = counter - highest
            bitmap = shift >= Self.size ? 0 : (bitmap << shift)
            bitmap |= 1
            highest = counter
            return .accepted
        }

        let distance = highest - counter
        if distance >= Self.size {
            return .rejectedTooOld
        }

        let mask: UInt64 = 1 << distance
        if bitmap & mask != 0 {
            return .rejectedReplay
        }
        bitmap |= mask
        return .accepted
    }

    /// The separate, application-level "don't apply if too far behind" check (spec §3.5.4):
    /// "an accepted motion datagram whose counter is more than 8 below the highest applied counter is
    /// not applied (its deltas are discarded) — relative deltas that arrive very late would otherwise
    /// produce a visible jump."
    ///
    /// This is independent of the replay window's 64-wide bitmap: a datagram can be accepted by
    /// `accept(_:)` (i.e. not a replay) and still be stale-to-apply by this rule, because "highest
    /// applied" tracks only counters whose deltas were actually applied to the pointer, which can lag
    /// behind "highest accepted" when datagrams within the 8-window arrive out of order
    /// (spec §3.5.4: "Datagrams within the 8-window are applied in arrival order").
    public static func isStaleToApply(counter: UInt64, highestApplied: UInt64) -> Bool {
        highestApplied > counter && (highestApplied - counter) > staleApplyThreshold
    }
}
