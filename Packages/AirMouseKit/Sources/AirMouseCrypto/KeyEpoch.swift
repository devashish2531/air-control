#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Pure model of the UDP key-rotation rule (spec §3.5.5, §7.3, §11.3):
///
/// - The host rotates when either direction's counter reaches **2³¹** datagrams, or **4 h** after the
///   key was issued, whichever comes first.
/// - The client switches to the new key on receipt; the host keeps accepting the previous `sessionID`
///   for **2 s**, then discards it. Two keys maximum are live per session at any moment.
///
/// `KeyEpoch` carries no clock or timer of its own — every decision method takes `now`/`rotatedAt`
/// explicitly — so it is deterministic and trivially testable (arch §3.1 rule: pure value types with
/// state machines, no injected `Clock` needed here since there is no repeated polling, just point-in-time
/// decisions made by the caller's own event loop).
public struct KeyEpoch: Sendable, Equatable {
    /// Rotate after this much wall-clock time since the epoch was issued (spec §3.5.5, §11.3).
    // TODO(integration): move to ProtocolConstants.
    public static let rotationInterval: TimeInterval = 4 * 60 * 60

    /// Rotate once a direction's counter reaches this many datagrams (spec §3.5.5, §11.3: `2^31`).
    // TODO(integration): move to ProtocolConstants.
    public static let maxDatagramsPerDirection: UInt64 = 1 << 31

    /// How long the host keeps accepting the *previous* `sessionID` after rotating (spec §3.5.5, §11.3).
    // TODO(integration): move to ProtocolConstants.
    public static let overlapWindow: TimeInterval = 2

    /// The `sessionID` this epoch's keys were derived for (spec §3.5.3).
    public let sessionID: UInt32

    /// When this epoch's `SessionSecret` was issued.
    public let issuedAt: Date

    public init(sessionID: UInt32, issuedAt: Date) {
        self.sessionID = sessionID
        self.issuedAt = issuedAt
    }

    /// Whether this epoch is due for rotation given how many datagrams have been sent in *either*
    /// direction so far, and the current time.
    ///
    /// - Parameters:
    ///   - datagramsSent: the higher of the two directional counters (c2h, h2c) observed so far.
    ///   - now: the current time.
    public func isRotationDue(datagramsSent: UInt64, now: Date) -> Bool {
        datagramsSent >= Self.maxDatagramsPerDirection || now.timeIntervalSince(issuedAt) >= Self.rotationInterval
    }

    /// The instant at which this epoch stops being accepted, given that rotation happened at
    /// `rotatedAt` (spec §3.5.5: "the host keeps accepting the previous sessionID for 2 s then
    /// discards it").
    public func retirementDeadline(rotatedAt: Date) -> Date {
        rotatedAt.addingTimeInterval(Self.overlapWindow)
    }

    /// Whether, given a rotation that happened at `rotatedAt`, this (now-previous) epoch's `sessionID`
    /// should still be accepted at `now`.
    public func isWithinOverlap(rotatedAt: Date, now: Date) -> Bool {
        now < retirementDeadline(rotatedAt: rotatedAt)
    }
}
