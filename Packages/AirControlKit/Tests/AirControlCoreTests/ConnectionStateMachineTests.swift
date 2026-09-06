import Testing
@testable import AirControlCore

@Suite struct ConnectionStateMachineTests {
    @Test func idleToBrowsingOnDevicesVisible() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .idle, event: .devicesVisible)
        #expect(state == .browsing)
        #expect(effects == [.startBrowsing])
    }

    @Test func idleToConnectingOnQRScanned() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .idle, event: .qrScanned)
        #expect(state == .connecting)
        #expect(effects == [.startConnecting])
    }

    @Test func browsingToIdleOnDevicesHidden() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .browsing, event: .devicesHiddenNoAutoConnect)
        #expect(state == .idle)
        #expect(effects == [.stopBrowsing, .notifyIdle])
    }

    @Test func browsingToConnectingOnTrustedHostFound() {
        let (state, _) = ConnectionStateMachine.reduce(state: .browsing, event: .trustedHostFound)
        #expect(state == .connecting)
    }

    @Test func browsingToConnectingOnUserTappedConnect() {
        let (state, _) = ConnectionStateMachine.reduce(state: .browsing, event: .userTappedConnect)
        #expect(state == .connecting)
    }

    @Test func browsingToConnectingOnQRScanned() {
        let (state, _) = ConnectionStateMachine.reduce(state: .browsing, event: .qrScanned)
        #expect(state == .connecting)
    }

    @Test func connectingToPairingOnTLSReadyPairing() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .connecting, event: .tlsReadyPairing)
        #expect(state == .pairing)
        #expect(effects == [.startPairingFlow])
    }

    @Test func connectingToConnectedOnTLSReadyTrusted() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .connecting, event: .tlsReadyTrustedHelloAck)
        #expect(state == .connected)
        #expect(effects == [.notifyConnected])
    }

    @Test func connectingToFailedOnAllCandidatesFailed() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .connecting, event: .allCandidatesFailed)
        #expect(state == .failed(.allCandidatesFailed))
        #expect(effects == [.notifyFailed(.allCandidatesFailed)])
    }

    @Test func connectingToFailedOnFatalError() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .connecting, event: .fatalError("boom"))
        #expect(state == .failed(.fatal("boom")))
        #expect(effects == [.notifyFailed(.fatal("boom"))])
    }

    @Test func connectingToFailedOnLocalNetworkDenied() {
        let (state, _) = ConnectionStateMachine.reduce(state: .connecting, event: .localNetworkDenied)
        #expect(state == .failed(.localNetworkDenied))
    }

    @Test func pairingToConnectedOnPairConfirmVerified() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .pairing, event: .pairConfirmVerifiedAndHelloAck)
        #expect(state == .connected)
        #expect(effects == [.notifyConnected])
    }

    @Test func pairingToFailedOnPairingError() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .pairing, event: .pairingError)
        #expect(state == .failed(.pairingFailed))
        #expect(effects == [.notifyFailed(.pairingFailed)])
    }

    @Test func connectedToReconnectingOnNoPongTimeout() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .connected, event: .noPongTimeout)
        #expect(state == .reconnecting)
        #expect(effects == [.beginReconnectLoop])
    }

    @Test func connectedToReconnectingOnConnectionFailed() {
        let (state, _) = ConnectionStateMachine.reduce(state: .connected, event: .connectionFailed)
        #expect(state == .reconnecting)
    }

    @Test func connectedToReconnectingOnPathChanged() {
        let (state, _) = ConnectionStateMachine.reduce(state: .connected, event: .pathChanged)
        #expect(state == .reconnecting)
    }

    @Test func connectedToIdleOnUserDisconnected() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .connected, event: .userDisconnectedOrForgetOrGoodbye)
        #expect(state == .idle)
        #expect(effects == [.notifyIdle])
    }

    @Test func connectedToSuspendedOnScenePhaseInactive() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .connected, event: .scenePhaseInactive)
        #expect(state == .suspended)
        #expect(effects == [.suspendConnections])
    }

    @Test func reconnectingToConnectedOnNewSessionReady() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .reconnecting, event: .newSessionReady)
        #expect(state == .connected)
        #expect(effects == [.notifyConnected])
    }

    @Test func reconnectingToSuspendedOnScenePhaseInactive() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .reconnecting, event: .scenePhaseInactive)
        #expect(state == .suspended)
        #expect(effects == [.cancelReconnectLoop, .suspendConnections])
    }

    @Test func reconnectingToFailedOnUserCancelled() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .reconnecting, event: .userCancelled)
        #expect(state == .failed(.userCancelled))
        #expect(effects == [.cancelReconnectLoop, .notifyFailed(.userCancelled)])
    }

    @Test func reconnectingToFailedOnGiveUpElapsed() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .reconnecting, event: .reconnectGiveUpElapsed)
        #expect(state == .failed(.reconnectGiveUpElapsed))
        #expect(effects == [.cancelReconnectLoop, .notifyFailed(.reconnectGiveUpElapsed)])
    }

    @Test func suspendedToConnectingOnScenePhaseActive() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .suspended, event: .scenePhaseActive)
        #expect(state == .connecting)
        #expect(effects == [.resumeImmediately, .startConnecting])
    }

    @Test func failedToBrowsingOnRetryTapped() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .failed(.allCandidatesFailed), event: .retryTapped)
        #expect(state == .browsing)
        #expect(effects == [.startBrowsing])
    }

    @Test func failedToBrowsingOnDevicesVisible() {
        let (state, _) = ConnectionStateMachine.reduce(state: .failed(.pairingFailed), event: .devicesVisible)
        #expect(state == .browsing)
    }

    @Test func failedToConnectingOnQRScanned() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .failed(.allCandidatesFailed), event: .qrScanned)
        #expect(state == .connecting)
        #expect(effects == [.startConnecting])
    }

    // MARK: - Invalid transitions: state and effects are unchanged.

    @Test func idleIgnoresNoPongTimeout() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .idle, event: .noPongTimeout)
        #expect(state == .idle)
        #expect(effects.isEmpty)
    }

    @Test func connectedIgnoresQRScanned() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .connected, event: .qrScanned)
        #expect(state == .connected)
        #expect(effects.isEmpty)
    }

    @Test func pairingIgnoresDevicesVisible() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .pairing, event: .devicesVisible)
        #expect(state == .pairing)
        #expect(effects.isEmpty)
    }

    @Test func browsingIgnoresNewSessionReady() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .browsing, event: .newSessionReady)
        #expect(state == .browsing)
        #expect(effects.isEmpty)
    }

    @Test func suspendedIgnoresUserCancelled() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .suspended, event: .userCancelled)
        #expect(state == .suspended)
        #expect(effects.isEmpty)
    }

    @Test func reconnectingIgnoresDevicesVisible() {
        let (state, effects) = ConnectionStateMachine.reduce(state: .reconnecting, event: .devicesVisible)
        #expect(state == .reconnecting)
        #expect(effects.isEmpty)
    }
}
