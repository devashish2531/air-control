import Testing
@testable import AirControlCore

@Suite struct HostSessionStateMachineTests {
    @Test func knownPeerAuthenticatesOnHelloPairingFalse() {
        let (state, effects) = HostSessionStateMachine.reduce(state: .tlsAccepted(peer: .known), event: .helloReceivedPairingFalse)
        #expect(state == .authenticated)
        #expect(effects == [.completeAuthentication])
    }

    /// Spec decision (§3.2/§3.3 don't define this): a known peer's `hello { pairing: true }` — the
    /// device re-scanned a pairing QR while this Mac already trusts its certificate — runs through
    /// the same pairing flow as an unknown peer, rather than authenticating immediately without
    /// ever answering `pairChallenge`/`pairConfirm` (which used to hang the client's
    /// `ClientSession.pair(url:)` until the 6 s no-heartbeat watchdog closed the connection).
    /// `HostSession.beginPairingChallenge` then decides, from the pairing window's own state,
    /// whether to actually run the challenge/proof round trip or answer `pairing.alreadyTrusted`.
    @Test func knownPeerEntersPairingFlowOnHelloPairingTrue() {
        let (state, effects) = HostSessionStateMachine.reduce(state: .tlsAccepted(peer: .known), event: .helloReceivedPairingTrue)
        #expect(state == .pairing)
        #expect(effects == [.beginPairingFlow])
    }

    @Test func unknownPeerEntersPairingOnHelloPairingTrue() {
        let (state, effects) = HostSessionStateMachine.reduce(state: .tlsAccepted(peer: .unknown), event: .helloReceivedPairingTrue)
        #expect(state == .pairing)
        #expect(effects == [.beginPairingFlow])
    }

    @Test func unknownPeerClosesOnHelloPairingFalse() {
        let (state, effects) = HostSessionStateMachine.reduce(state: .tlsAccepted(peer: .unknown), event: .helloReceivedPairingFalse)
        #expect(state == .closing)
        #expect(effects == [.sendAuthUntrustedAndClose])
    }

    @Test func unknownPeerClosesOnNonPairMessage() {
        let (state, effects) = HostSessionStateMachine.reduce(state: .tlsAccepted(peer: .unknown), event: .nonPairMessageWhileUnauthenticated)
        #expect(state == .closing)
        #expect(effects == [.sendAuthUntrustedAndClose])
    }

    @Test func pairingClosesOnNonPairMessage() {
        let (state, effects) = HostSessionStateMachine.reduce(state: .pairing, event: .nonPairMessageWhileUnauthenticated)
        #expect(state == .closing)
        #expect(effects == [.sendAuthUntrustedAndClose])
    }

    @Test func pairingAuthenticatesOnProofAccepted() {
        let (state, effects) = HostSessionStateMachine.reduce(state: .pairing, event: .pairProofAccepted)
        #expect(state == .authenticated)
        #expect(effects == [.completeAuthentication])
    }

    @Test func pairingClosesOnPairingFailed() {
        let (state, effects) = HostSessionStateMachine.reduce(state: .pairing, event: .pairingFailed)
        #expect(state == .closing)
        #expect(effects == [.sendPairingErrorAndClose])
    }

    @Test func authenticatedGoesStaleOnNoHeartbeat2s() {
        let (state, effects) = HostSessionStateMachine.reduce(state: .authenticated, event: .noHeartbeatFor2s)
        #expect(state == .stale)
        #expect(effects == [.releaseHeldInputsAndMarkStale])
    }

    @Test func authenticatedClosesOnNoHeartbeat6s() {
        let (state, effects) = HostSessionStateMachine.reduce(state: .authenticated, event: .noHeartbeatFor6s)
        #expect(state == .closing)
        #expect(effects == [.closeConnection])
    }

    @Test func staleRestoresOnHeartbeatReceived() {
        let (state, effects) = HostSessionStateMachine.reduce(state: .stale, event: .heartbeatReceived)
        #expect(state == .authenticated)
        #expect(effects == [.restoreFromStale])
    }

    @Test func staleClosesOnNoHeartbeat6s() {
        let (state, effects) = HostSessionStateMachine.reduce(state: .stale, event: .noHeartbeatFor6s)
        #expect(state == .closing)
        #expect(effects == [.closeConnection])
    }

    @Test func authenticatedClosesOnGoodbye() {
        let (state, effects) = HostSessionStateMachine.reduce(state: .authenticated, event: .goodbyeReceived)
        #expect(state == .closing)
        #expect(effects == [.closeConnection])
    }

    @Test func pairingClosesOnCloseRequested() {
        let (state, effects) = HostSessionStateMachine.reduce(state: .pairing, event: .closeRequested)
        #expect(state == .closing)
        #expect(effects == [.closeConnection])
    }

    // MARK: - Invalid transitions

    @Test func authenticatedIgnoresHelloReceivedPairingTrue() {
        let (state, effects) = HostSessionStateMachine.reduce(state: .authenticated, event: .helloReceivedPairingTrue)
        #expect(state == .authenticated)
        #expect(effects.isEmpty)
    }

    @Test func closingIgnoresHeartbeatReceived() {
        let (state, effects) = HostSessionStateMachine.reduce(state: .closing, event: .heartbeatReceived)
        #expect(state == .closing)
        #expect(effects.isEmpty)
    }

    @Test func tlsAcceptedKnownIgnoresPairProofAccepted() {
        let (state, effects) = HostSessionStateMachine.reduce(state: .tlsAccepted(peer: .known), event: .pairProofAccepted)
        #expect(state == .tlsAccepted(peer: .known))
        #expect(effects.isEmpty)
    }

    @Test func staleIgnoresNonPairMessage() {
        let (state, effects) = HostSessionStateMachine.reduce(state: .stale, event: .nonPairMessageWhileUnauthenticated)
        #expect(state == .stale)
        #expect(effects.isEmpty)
    }
}
