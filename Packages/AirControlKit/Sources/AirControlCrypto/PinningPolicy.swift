/// Pure accept/reject decision for a TLS verify block, given a peer fingerprint and trust context —
/// no `Security`/`Network` types, so it's usable identically by the host and client verify blocks and
/// is trivially unit-testable.
///
/// Host side (spec §3.2.1):
/// > accept iff (a) FP is in the trusted store and not revoked → session state `authenticated`, or
/// > (b) a Pairing window is open **and** the pending-connection count < 2 → session state
/// > `unauthenticated` (only `hello` with `pairing:true` and `pair*` messages are accepted; anything
/// > else closes the connection with `auth.untrusted`). Otherwise reject.
///
/// Client side (spec §3.2.1): "accept iff FP == pinned FP for this host". `PinningPolicy.client` covers
/// that half, though a single `Fingerprint ==` compare is usually enough on its own — it exists here so
/// both apps call one shared, named policy instead of open-coding the comparison.
public enum PinningPolicy: Sendable {
    /// Maximum simultaneous pending (unauthenticated, in-pairing-window) connections (spec §3.2.1,
    /// §7.6, §11.3: "Pending pairing connections | 2").
    // TODO(integration): move to ProtocolConstants.
    public static let maxPendingPairingConnections = 2

    /// Required certificate chain length (spec §3.2.1: "Chain length must be exactly 1", both sides).
    public static let requiredChainLength = 1

    /// The host's decision for one incoming client certificate.
    public enum HostDecision: Sendable, Equatable {
        /// FP is a known, non-revoked trusted device → session state `authenticated`.
        case trusted
        /// FP is unknown but a pairing window is open and there is room for another pending
        /// connection → session state `unauthenticated`, confined to `pair*` messages.
        case pendingPairing
        /// Neither of the above: TLS alert `certificate_unknown` (spec §3.2.6).
        case reject
    }

    /// Host verify-block decision (spec §3.2.1).
    ///
    /// - Parameters:
    ///   - chainLength: length of the peer's certificate chain (must be exactly 1).
    ///   - peerFingerprint: the leaf certificate's fingerprint.
    ///   - trustedFingerprints: the host's trusted-device fingerprint set (revoked devices already
    ///     excluded by the caller — spec §3.2.1 says "trusted store and not revoked").
    ///   - pairingWindowOpen: whether a pairing window is currently open.
    ///   - pendingConnectionCount: how many unauthenticated pending connections already exist.
    public static func hostDecision(
        chainLength: Int,
        peerFingerprint: Fingerprint,
        trustedFingerprints: Set<Fingerprint>,
        pairingWindowOpen: Bool,
        pendingConnectionCount: Int
    ) -> HostDecision {
        guard chainLength == requiredChainLength else { return .reject }
        if trustedFingerprints.contains(peerFingerprint) {
            return .trusted
        }
        if pairingWindowOpen && pendingConnectionCount < maxPendingPairingConnections {
            return .pendingPairing
        }
        return .reject
    }

    /// Client verify-block decision (spec §3.2.1): accept iff chain length is 1 and the peer FP equals
    /// the pinned host FP (constant-time compare, since `Fingerprint.==` already is).
    public static func clientAccepts(
        chainLength: Int,
        peerFingerprint: Fingerprint,
        pinnedFingerprint: Fingerprint
    ) -> Bool {
        chainLength == requiredChainLength && peerFingerprint == pinnedFingerprint
    }
}
