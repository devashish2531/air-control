import Foundation

/// `ConnectionManager`'s client-side connection state (spec §4.5.1). `Suspended` is the spec's
/// own addendum to the seven "required" states: "`Suspended` is added to the seven required
/// states to make background handling explicit."
public enum ConnectionState: Sendable, Equatable, Hashable {
    case idle
    case browsing
    case connecting
    case pairing
    case connected
    case reconnecting
    case suspended
    case failed(ConnectionFailureReason)
}

/// Why `Connecting`/`Pairing`/`Reconnecting` moved to `Failed` (spec §4.5.1, §4.5.5).
public enum ConnectionFailureReason: Sendable, Equatable, Hashable {
    /// spec §4.5.1: "all candidates failed (4 s each)".
    case allCandidatesFailed
    /// spec §4.5.1: "fatal error" while `Connecting`.
    case fatal(String)
    /// spec §4.5.1: "pairing error" while `Pairing`.
    case pairingFailed
    /// spec §4.5.1: "user cancels" while `Reconnecting`.
    case userCancelled
    /// spec §4.5.1 / §4.5.2: "10 min elapsed" while `Reconnecting`.
    case reconnectGiveUpElapsed
    /// spec §4.5.5: local network permission denied.
    case localNetworkDenied
}

/// Events `ConnectionStateMachine.reduce` consumes (spec §4.5.1's mermaid edge labels, one event
/// per edge condition).
public enum ConnectionEvent: Sendable, Equatable, Hashable {
    /// spec: "Devices visible" (Devices tab shown) or "auto-connect pending".
    case devicesVisible
    /// spec: "Devices hidden and no auto-connect".
    case devicesHiddenNoAutoConnect
    /// spec: "trusted host found" (Bonjour) while `Browsing`.
    case trustedHostFound
    /// spec: "user tapped Connect" while `Browsing`.
    case userTappedConnect
    /// spec: "QR scanned" — direct addresses, valid from `Idle`, `Browsing`, or `Failed`.
    case qrScanned
    /// spec: "TLS ready and pairing true".
    case tlsReadyPairing
    /// spec: "TLS ready and helloAck (trusted)" — a trusted reconnect completed in one hop.
    case tlsReadyTrustedHelloAck
    /// spec: "all candidates failed (4 s each)".
    case allCandidatesFailed
    /// spec: "fatal error" while `Connecting`.
    case fatalError(String)
    /// spec: "pairConfirm verified and helloAck".
    case pairConfirmVerifiedAndHelloAck
    /// spec: "pairing error".
    case pairingError
    /// spec: "no pong 2 s".
    case noPongTimeout
    /// spec: "connection failed" while `Connected`.
    case connectionFailed
    /// spec: "path changed" while `Connected`.
    case pathChanged
    /// spec: "user Disconnect / Forget / goodbye".
    case userDisconnectedOrForgetOrGoodbye
    /// spec: "scenePhase != active".
    case scenePhaseInactive
    /// spec: "scenePhase == active (immediate)".
    case scenePhaseActive
    /// spec: "new session ready" while `Reconnecting`.
    case newSessionReady
    /// spec: "user cancels" while `Reconnecting`.
    case userCancelled
    /// spec: "10 min elapsed" while `Reconnecting`.
    case reconnectGiveUpElapsed
    /// spec: "Retry" while `Failed`.
    case retryTapped
    /// spec §4.5.5: local network permission denied.
    case localNetworkDenied
}

/// Side effects the reducer requests; the caller's actor (`ConnectionManager` in the apps)
/// performs them. Pure by construction — `ConnectionStateMachine` never touches `Network`,
/// timers, or I/O itself (arch §3.1: "the kit contains no actors ... State machines are pure
/// reducers returning effects").
public enum ConnectionEffect: Sendable, Equatable, Hashable {
    case startBrowsing
    case stopBrowsing
    case startConnecting
    case cancelConnecting
    case startPairingFlow
    case beginReconnectLoop
    case cancelReconnectLoop
    case suspendConnections
    case resumeImmediately
    case notifyFailed(ConnectionFailureReason)
    case notifyConnected
    case notifyIdle
}
