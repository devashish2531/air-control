// NWDatagramChannel + NWUDPHub — Network.framework implementation of `AirControlCore.DatagramChannel`
// for the host side of the motion (UDP) path (spec §3.5.1, §3.5.8's probe reply path, §7.6's DoS
// bound). Owned by the networking agent (assignment: "Services/HostServer/").
//
// `NWListener(using: .udp)` yields one `NWConnection` per remote 5-tuple (docs/02-technical-
// research.md §B4: "index by session ID, not by tuple, so a phone changing ports keeps its
// session"), so `NWUDPHub` is the single owner of the listener and every accepted connection; it
// demultiplexes incoming datagrams by the clear 4-byte `sessionID` header (spec §3.5.1) to
// whichever `NWDatagramChannel` `HostServer`/`SessionManager` registered for that session, and
// remembers which `NWConnection` last delivered a given `sessionID` so a reply (e.g. a probe echo,
// spec §3.5.8) goes back to the sender's current endpoint even if its UDP port changed.
import AirControlCore
import AirControlCrypto
import AirControlProtocol
import Foundation
import Network
import os

/// One session's UDP datagram channel, vended by `NWUDPHub.register(sessionID:)`. `send` is
/// synchronous (matching `AirControlCore.DatagramChannel`'s non-`async` `send(_:) throws` — the
/// caller, `HostSession`, calls it as `try? channel.send(...)` from inside an already-isolated
/// context) and simply hands the datagram to the hub, which posts it on whatever `NWConnection`
/// last delivered a datagram for this `sessionID`; best-effort, matching UDP's own semantics.
public final class NWDatagramChannel: DatagramChannel, @unchecked Sendable {
    let sessionID: UInt32
    private weak var hub: NWUDPHub?

    public let incoming: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation

    init(sessionID: UInt32, hub: NWUDPHub) {
        self.sessionID = sessionID
        self.hub = hub
        var cont: AsyncStream<Data>.Continuation!
        self.incoming = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    /// Called by `NWUDPHub` when a datagram for this session arrives.
    func deliver(_ data: Data) {
        continuation.yield(data)
    }

    public func send(_ datagram: Data) throws {
        hub?.send(datagram, forSessionID: sessionID)
    }

    public func close() {
        continuation.finish()
        hub?.unregister(sessionID: sessionID)
    }
}

/// Owns the single host-side `NWListener(using: .udp)` (spec §5.1.5's Bonjour UDP record pairs with
/// this listener's port) and every accepted per-remote-endpoint `NWConnection`. Not an `actor` —
/// `NWDatagramChannel.send` must stay synchronous to match `DatagramChannel`'s protocol shape, so
/// this type instead protects its tables with `OSAllocatedUnfairLock` (async-safe, unlike `NSLock`)
/// and runs every listener/connection callback on one dedicated `.userInteractive` queue (spec
/// §5.1.1: networking on a dedicated `DispatchQueue("net", qos: .userInteractive)`).
public final class NWUDPHub: @unchecked Sendable {
    private struct State {
        var listener: NWListener?
        var retainedConnections: [ObjectIdentifier: NWConnection] = [:]
        var connectionBySessionID: [UInt32: NWConnection] = [:]
        var channelBySessionID: [UInt32: NWDatagramChannel] = [:]
        /// Bumped on every datagram rejected before it reaches `AirControlCore` (wrong length, or a
        /// `sessionID` with no registered channel) — spec §3.5.1: "dropped silently and counted".
        var droppedBeforeDecryptCount: Int = 0
    }

    private let queue: DispatchQueue
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(queueLabel: String = "com.aircontrol.helper.net.udp") {
        self.queue = DispatchQueue(label: queueLabel, qos: .userInteractive)
    }

    /// The bound UDP port, once `start(port:)` has succeeded.
    public var boundPort: UInt16? {
        state.withLock { $0.listener?.port?.rawValue }
    }

    /// spec §3.5.1: "dropped silently and counted".
    public var droppedBeforeDecryptCount: Int {
        state.withLock { $0.droppedBeforeDecryptCount }
    }

    /// Starts the UDP listener and waits for it to actually bind (`.ready`) before returning —
    /// `NWListener.port` can otherwise still report the *requested* port (e.g. `.any`, rawValue 0)
    /// for a brief window after `start(queue:)` returns, which would otherwise race `boundPort`'s
    /// readers (`HostServer`'s Bonjour/pairing-URL/accept-time UDP-port lookups). `port == 0`
    /// requests an ephemeral port (spec §5.1.5 port-busy fallback); `loopbackOnly` restricts to the
    /// loopback interface (`--loopback`, spec §8 launch arguments).
    public func start(port: UInt16, loopbackOnly: Bool) async throws {
        let params = NWParameters.udp
        params.includePeerToPeer = false // spec §3.1.1: "includePeerToPeer = false on both sides (no AWDL)."
        if loopbackOnly {
            params.requiredInterfaceType = .loopback
        }
        let nwPort = port == 0 ? NWEndpoint.Port.any : (NWEndpoint.Port(rawValue: port) ?? .any)
        let listener = try NWListener(using: params, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        state.withLock { $0.listener = listener }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { listenerState in
                switch listenerState {
                case .ready: continuation.resume()
                case .failed(let error): continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    public func stop() {
        let (connections, currentListener) = state.withLock { s -> ([NWConnection], NWListener?) in
            let connections = Array(s.retainedConnections.values)
            let currentListener = s.listener
            s.retainedConnections.removeAll()
            s.connectionBySessionID.removeAll()
            s.channelBySessionID.removeAll()
            s.listener = nil
            return (connections, currentListener)
        }
        connections.forEach { $0.cancel() }
        currentListener?.cancel()
    }

    /// Registers a fresh `NWDatagramChannel` to receive datagrams for `sessionID` (called once a
    /// `HostSession` has issued its `sessionKey`, spec §3.3.1).
    public func register(sessionID: UInt32) -> NWDatagramChannel {
        let channel = NWDatagramChannel(sessionID: sessionID, hub: self)
        state.withLock { $0.channelBySessionID[sessionID] = channel }
        return channel
    }

    func unregister(sessionID: UInt32) {
        state.withLock {
            $0.channelBySessionID.removeValue(forKey: sessionID)
            $0.connectionBySessionID.removeValue(forKey: sessionID)
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        state.withLock { $0.retainedConnections[id] = connection }
        connection.stateUpdateHandler = { [weak self, weak connection] connState in
            switch connState {
            case .failed, .cancelled:
                guard let connection else { return }
                self?.dropConnection(connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveNext(on: connection)
    }

    private func dropConnection(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        state.withLock {
            $0.retainedConnections.removeValue(forKey: id)
            $0.connectionBySessionID = $0.connectionBySessionID.filter { $0.value !== connection }
        }
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty, let connection {
                self.route(data: data, from: connection)
            }
            if error == nil, let connection {
                self.receiveNext(on: connection)
            } else if let connection {
                self.dropConnection(connection)
            }
        }
    }

    private func route(data: Data, from connection: NWConnection) {
        // spec §3.5.1 / §7.6: "exactly 44 bytes ... unknown sessionID dropped before AEAD."
        guard data.count == ProtocolConstants.udpDatagramSize,
              let header = MotionDatagramHeader(bytes: Array(data.prefix(MotionDatagramHeader.byteCount)))
        else {
            state.withLock { $0.droppedBeforeDecryptCount += 1 }
            return
        }
        let channel = state.withLock { s -> NWDatagramChannel? in
            s.connectionBySessionID[header.sessionID] = connection
            let channel = s.channelBySessionID[header.sessionID]
            if channel == nil { s.droppedBeforeDecryptCount += 1 }
            return channel
        }
        channel?.deliver(data)
    }

    /// Sends `datagram` on whatever `NWConnection` most recently delivered a datagram for
    /// `sessionID` (spec §3.5.8: probe replies "use the sender's endpoint"). Silently does nothing
    /// if no connection is known yet (e.g. the host has nothing to reply to before the client's
    /// first datagram arrives).
    func send(_ datagram: Data, forSessionID sessionID: UInt32) {
        let connection = state.withLock { $0.connectionBySessionID[sessionID] }
        connection?.send(content: datagram, completion: .contentProcessed { _ in })
    }
}
