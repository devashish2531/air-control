import Foundation

/// Known dotted-namespace error codes carried in the wire `error` message's `code` field.
/// spec §3.4.5: "`code` str (dotted namespace: `protocol.*`, `auth.*`, `pairing.*`, `rate.*`,
/// `host.*`, `macro.*`, `internal`)". spec §3.2.6 and §3.4 enumerate the concrete values below.
///
/// The wire field itself is a plain `String` (see `ErrorPayload.code`), not this enum, so an
/// unrecognized code from a newer peer round-trips instead of failing to decode (§3.4.2: "Unknown
/// fields → ignored"). Use `ErrorPayload.knownCode` to recover a typed value when possible.
public enum ErrorCode: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// spec §3.0 / §3.4.1: frame body exceeded 256 KiB.
    case frameTooLarge = "protocol.frameTooLarge"
    /// spec §3.4.1: unknown frame `kind`.
    case badFrame = "protocol.badFrame"
    /// spec §3.4.2: missing required field in a known message type.
    case badMessage = "protocol.badMessage"
    /// spec §3.2.6 / §3.4.4: no protocol version range in common.
    case versionMismatch = "protocol.versionMismatch"
    /// spec §3.2.6: unknown client certificate, no pairing window open.
    case authUntrusted = "auth.untrusted"
    /// spec §3.2.6: client certificate matches a revoked trusted-device record.
    case authRevoked = "auth.revoked"
    /// spec §3.2.6: pairing window closed or secret expired.
    case pairingExpired = "pairing.expired"
    /// spec §3.2.6: `pairProof` failed to verify.
    case pairingInvalidProof = "pairing.invalidProof"
    /// spec §3.2.6: host already has `maxTrustedDevicesPerHost` trusted devices.
    case pairingTooManyDevices = "pairing.tooManyDevices"
    /// spec §3.0 / §3.4.5: control message rate limit exceeded.
    case rateLimited = "rate.limited"
    /// spec §5.5.5: script/shortcut macro blocked by host policy.
    case macroBlockedByPolicy = "macro.blockedByPolicy"
    /// Not part of the original spec (§3.2/§3.3 don't define re-pairing an already-trusted
    /// device): a peer whose certificate the host already trusts sent `hello { pairing: true }`
    /// (re-scanned a pairing QR) while no pairing window was open, so there was nothing to prove
    /// against. Distinct from `pairing.expired` — that wording tells an *unknown* peer "the code
    /// timed out, scan a fresh one"; this one tells an already-trusted peer "you don't need to
    /// pair at all, just reconnect" (spec §3.3.1).
    case alreadyTrusted = "pairing.alreadyTrusted"
    /// Unclassified host-side failure.
    case internalError = "internal"
}
