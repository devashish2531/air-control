import Foundation

/// Whether the peer certificate observed at TLS accept time was already in the trusted-device
/// store (spec §3.2.1's host verify block decision, `AirMouseCrypto.PinningPolicy.HostDecision`
/// narrowed to the two "let the TLS handshake proceed" outcomes — `.reject` never reaches a
/// `HostSessionStateMachine` at all, since the host closes the handshake itself).
public enum HostPeerKnowledge: Sendable, Equatable, Hashable {
    case known
    case unknown
}

/// Per-connection host-side session state (spec §3.2.1, §3.2.2, §3.4.6). Mirrors the client-side
/// `ConnectionStateMachine` in spirit: a pure reducer, no actors, no I/O (arch §3.1).
public enum HostSessionState: Sendable, Equatable, Hashable {
    /// Just past the TLS handshake, before `hello` has arrived. `peer` records which of the two
    /// spec §3.2.1 accept paths let the handshake through.
    case tlsAccepted(peer: HostPeerKnowledge)
    /// Unknown peer, pairing window was open at accept time: confined to `hello`/`pair*`
    /// messages until a proof is verified (spec §3.2.1(b)).
    case pairing
    /// Fully authenticated: every message type is accepted (spec §3.2.1(a), or pairing completed).
    case authenticated
    /// No `heartbeat` for 2 s: held inputs released, motion no longer accepted, but the TCP
    /// connection stays open until either a heartbeat resumes it or 6 s total elapses (spec
    /// §3.4.6).
    case stale
    /// Connection is being torn down (fatal error sent/received, `goodbye`, or the 6 s timeout).
    case closing
}

/// Events `HostSessionStateMachine.reduce` consumes.
public enum HostSessionEvent: Sendable, Equatable {
    /// TLS handshake completed; `peer` is the verify-block's decision (spec §3.2.1). A `.reject`
    /// decision never reaches this state machine — the host aborts the handshake itself before a
    /// session (and therefore a state machine instance) exists.
    case tlsHandshakeCompleted(peer: HostPeerKnowledge)
    case helloReceivedPairingTrue
    case helloReceivedPairingFalse
    case pairProofAccepted
    case pairingFailed
    /// spec §3.2.6: "Non-pair message while unauthenticated | Host | `error "auth.untrusted"`, close".
    case nonPairMessageWhileUnauthenticated
    /// spec §3.4.6: "no `heartbeat` for 2 000 ms → ... mark the session `stale`".
    case noHeartbeatFor2s
    /// A `heartbeat` arrived while `stale`, restoring the session.
    case heartbeatReceived
    /// spec §3.4.6: "no heartbeat for 6 000 ms → close TCP".
    case noHeartbeatFor6s
    case goodbyeReceived
    case closeRequested
}

/// Side effects the reducer requests; `HostSession` (the actor) performs them.
public enum HostSessionEffect: Sendable, Equatable {
    case sendAuthUntrustedAndClose
    case sendPairingErrorAndClose
    case beginPairingFlow
    case completeAuthentication
    case releaseHeldInputsAndMarkStale
    case restoreFromStale
    case closeConnection
}

public enum HostSessionStateMachine {
    /// Reduces one event against `state` (spec §3.2.1, §3.2.2, §3.2.6, §3.4.6). As with
    /// `ConnectionStateMachine`, an event with no modeled transition from the current state
    /// returns the same state and no effects.
    public static func reduce(
        state: HostSessionState,
        event: HostSessionEvent
    ) -> (state: HostSessionState, effects: [HostSessionEffect]) {
        switch (state, event) {

        case (.tlsAccepted(let peer), .tlsHandshakeCompleted):
            // Re-delivering the acceptance event is a no-op; the state already reflects it.
            return (.tlsAccepted(peer: peer), [])

        // Known peer: `hello { pairing: false }` (or, unusually, true) both authenticate — the
        // certificate alone already proved trust (spec §3.2.1(a)); pairing again is harmless.
        case (.tlsAccepted(.known), .helloReceivedPairingFalse), (.tlsAccepted(.known), .helloReceivedPairingTrue):
            return (.authenticated, [.completeAuthentication])

        // Unknown peer, window was open at accept: only a pairing hello is acceptable.
        case (.tlsAccepted(.unknown), .helloReceivedPairingTrue):
            return (.pairing, [.beginPairingFlow])
        case (.tlsAccepted(.unknown), .helloReceivedPairingFalse):
            return (.closing, [.sendAuthUntrustedAndClose])
        case (.tlsAccepted(.unknown), .nonPairMessageWhileUnauthenticated):
            return (.closing, [.sendAuthUntrustedAndClose])

        case (.pairing, .pairProofAccepted):
            return (.authenticated, [.completeAuthentication])
        case (.pairing, .pairingFailed):
            return (.closing, [.sendPairingErrorAndClose])
        case (.pairing, .nonPairMessageWhileUnauthenticated):
            return (.closing, [.sendAuthUntrustedAndClose])

        case (.authenticated, .noHeartbeatFor2s):
            return (.stale, [.releaseHeldInputsAndMarkStale])
        case (.authenticated, .noHeartbeatFor6s):
            return (.closing, [.closeConnection])

        case (.stale, .heartbeatReceived):
            return (.authenticated, [.restoreFromStale])
        case (.stale, .noHeartbeatFor6s):
            return (.closing, [.closeConnection])

        case (_, .goodbyeReceived), (_, .closeRequested):
            return (.closing, [.closeConnection])

        default:
            return (state, [])
        }
    }
}
