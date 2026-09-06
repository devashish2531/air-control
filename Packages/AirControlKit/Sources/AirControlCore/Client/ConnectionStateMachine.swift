import Foundation

/// Pure reducer for the client-side connection state machine (spec §4.5.1). `AirControlCore`
/// contains no actors (arch §3.1); the apps' `ConnectionManager` actor drives real timers/`Network`
/// calls and feeds events in, executing whatever `ConnectionEffect`s come back.
///
/// `reduce` never throws and never leaves the state unspecified: an event that has no transition
/// from the current state (an "invalid transition") returns the *same* state and an empty effect
/// list, so callers/tests can distinguish "handled, no-op" only by checking effects — but every
/// transition explicitly modeled below is a mermaid edge from spec §4.5.1's diagram, doc-commented
/// with the edge's label.
public enum ConnectionStateMachine {
    /// Reduces one event against `state`, returning the next state and the effects to perform.
    public static func reduce(
        state: ConnectionState,
        event: ConnectionEvent
    ) -> (state: ConnectionState, effects: [ConnectionEffect]) {
        switch (state, event) {

        // Idle --> Browsing : Devices visible or auto-connect pending
        case (.idle, .devicesVisible):
            return (.browsing, [.startBrowsing])

        // Idle --> Connecting : QR scanned (direct addresses)
        case (.idle, .qrScanned):
            return (.connecting, [.startConnecting])

        // Browsing --> Idle : Devices hidden and no auto-connect
        case (.browsing, .devicesHiddenNoAutoConnect):
            return (.idle, [.stopBrowsing, .notifyIdle])

        // Browsing --> Connecting : trusted host found / user tapped Connect / QR scanned
        case (.browsing, .trustedHostFound), (.browsing, .userTappedConnect), (.browsing, .qrScanned):
            return (.connecting, [.stopBrowsing, .startConnecting])

        // Connecting --> Pairing : TLS ready and pairing true
        case (.connecting, .tlsReadyPairing):
            return (.pairing, [.startPairingFlow])

        // Connecting --> Connected : TLS ready and helloAck (trusted)
        case (.connecting, .tlsReadyTrustedHelloAck):
            return (.connected, [.notifyConnected])

        // Connecting --> Failed : all candidates failed (4 s each) / fatal error
        case (.connecting, .allCandidatesFailed):
            return (.failed(.allCandidatesFailed), [.notifyFailed(.allCandidatesFailed)])
        case (.connecting, .fatalError(let reason)):
            return (.failed(.fatal(reason)), [.notifyFailed(.fatal(reason))])

        // Pairing --> Connected : pairConfirm verified and helloAck
        case (.pairing, .pairConfirmVerifiedAndHelloAck):
            return (.connected, [.notifyConnected])

        // Pairing --> Failed : pairing error
        case (.pairing, .pairingError):
            return (.failed(.pairingFailed), [.notifyFailed(.pairingFailed)])

        // Connected --> Reconnecting : no pong 2 s / connection failed / path changed
        case (.connected, .noPongTimeout), (.connected, .connectionFailed), (.connected, .pathChanged):
            return (.reconnecting, [.beginReconnectLoop])

        // Connected --> Idle : user Disconnect / Forget / goodbye
        case (.connected, .userDisconnectedOrForgetOrGoodbye):
            return (.idle, [.notifyIdle])

        // Connected --> Suspended : scenePhase != active
        case (.connected, .scenePhaseInactive):
            return (.suspended, [.suspendConnections])

        // Reconnecting --> Connected : new session ready
        case (.reconnecting, .newSessionReady):
            return (.connected, [.notifyConnected])

        // Reconnecting --> Suspended : scenePhase != active
        case (.reconnecting, .scenePhaseInactive):
            return (.suspended, [.cancelReconnectLoop, .suspendConnections])

        // Reconnecting --> Failed : user cancels / 10 min elapsed
        case (.reconnecting, .userCancelled):
            return (.failed(.userCancelled), [.cancelReconnectLoop, .notifyFailed(.userCancelled)])
        case (.reconnecting, .reconnectGiveUpElapsed):
            return (.failed(.reconnectGiveUpElapsed), [.cancelReconnectLoop, .notifyFailed(.reconnectGiveUpElapsed)])

        // Suspended --> Connecting : scenePhase == active (immediate)
        case (.suspended, .scenePhaseActive):
            return (.connecting, [.resumeImmediately, .startConnecting])

        // Failed --> Browsing : Retry / Devices visible
        case (.failed, .retryTapped), (.failed, .devicesVisible):
            return (.browsing, [.startBrowsing])

        // Failed --> Connecting : QR scanned
        case (.failed, .qrScanned):
            return (.connecting, [.startConnecting])

        // spec §4.5.5: local network denied surfaces as Failed from any active attempt.
        case (.connecting, .localNetworkDenied):
            return (.failed(.localNetworkDenied), [.notifyFailed(.localNetworkDenied)])
        case (.browsing, .localNetworkDenied):
            return (.failed(.localNetworkDenied), [.stopBrowsing, .notifyFailed(.localNetworkDenied)])

        default:
            // No modeled transition: stay put, do nothing. Exhaustively tested as the "invalid
            // transition" half of the state-machine transition table.
            return (state, [])
        }
    }
}
