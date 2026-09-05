import Foundation
import AirMouseProtocol
import AirMouseCrypto

/// Negotiated session parameters from `helloAck` (spec §3.4.5), surfaced to the app once the
/// session reaches `Connected`.
public struct ConnectedInfo: Sendable, Equatable {
    public var protocolVersion: Int
    public var capabilities: [String]
    public var host: HelloAck.Host
    public var udpPort: Int
    public var heartbeatMs: Int
    public var sessionTimeoutMs: Int
    public var maxTextBytes: Int
    public var sessionCount: Int

    public init(ack: HelloAck) {
        protocolVersion = ack.protocol
        capabilities = ack.capabilities
        host = ack.host
        udpPort = ack.udpPort
        heartbeatMs = ack.heartbeatMs
        sessionTimeoutMs = ack.sessionTimeoutMs
        maxTextBytes = ack.maxTextBytes
        sessionCount = ack.sessionCount
    }
}

/// Events `ClientSession` delivers to the app via its `events: AsyncStream<ClientEvent>` (arch
/// §3.1: "incoming `HostState`/`MacroList`/`MacroResult`/`Error` delivery via an
/// `AsyncStream<ClientEvent>`").
public enum ClientEvent: Sendable, Equatable {
    /// `pairChallenge` arrived — the app may want to show "verifying…" UI.
    case pairingChallengeReceived(hostName: String)
    /// The host's `pairConfirm.hostProof` verified; the client now trusts (and, once the app
    /// persists it, will remember) this host's fingerprint.
    case paired(hostFingerprint: Fingerprint)
    /// `helloAck` (+ installed `sessionKey`) completed: the session is authenticated and the
    /// motion channel is ready.
    case connected(ConnectedInfo)
    case hostState(HostState)
    case macroList(MacroList)
    case macroResult(MacroResult)
    case error(ErrorPayload)
    case goodbye(GoodbyeReason)
    /// spec §3.5.8: UDP looks unhealthy; motion is now riding TCP batch frames.
    case fallbackEngaged
    /// spec §3.5.8: 5 consecutive probes answered; back on UDP.
    case fallbackRecovered
    case stats(SessionStats)
    /// The control channel closed (locally or by the peer); `reason` is diagnostic only.
    case disconnected(reason: String)
}
