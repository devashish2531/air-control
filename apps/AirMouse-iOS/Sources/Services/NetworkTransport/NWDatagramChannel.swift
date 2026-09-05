// Services/NetworkTransport/NWDatagramChannel.swift
// Client-side motion (UDP) channel implementing `AirMouseCore.DatagramChannel`, plus the
// `DatagramChannelProvider` factory `ClientSession` needs (spec §3.5 motion channel; arch's
// `ClientSession` doc comment: "the UDP port to connect to is only known once `helloAck.udpPort`
// arrives ... `datagramProvider` is the seam"). `.userInteractive` queue per this agent's brief —
// the motion path is the latency-sensitive one (spec §3.5.6/§3.5.7).

import Foundation
import Network
import AirMouseCore

/// One UDP "connection" (a bound 5-tuple; UDP itself has no handshake) to the host's motion port.
public final class NWDatagramChannel: DatagramChannel, @unchecked Sendable {
    private let connection: NWConnection

    public let incoming: AsyncStream<Data>
    private let incomingContinuation: AsyncStream<Data>.Continuation

    private init(connection: NWConnection) {
        self.connection = connection
        var continuation: AsyncStream<Data>.Continuation!
        self.incoming = AsyncStream { continuation = $0 }
        self.incomingContinuation = continuation
        startReceiveLoop()
    }

    /// Opens (starts) a UDP connection to `host:udpPort`. Resolves once the connection reaches
    /// `.ready` (for a connected UDP socket this is local-only setup, essentially immediate) or
    /// throws if it fails first.
    public static func connect(host: String, udpPort: Int) async throws -> NWDatagramChannel {
        guard let portValue = NWEndpoint.Port(rawValue: UInt16(clamping: udpPort)) else {
            throw TransportError.invalidPort(udpPort)
        }
        let queue = DispatchQueue(label: "com.airmouse.app.net.motion", qos: .userInteractive)
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = false // spec §3.1.1: "no AWDL" on either channel.

        let connection = NWConnection(host: NWEndpoint.Host(host), port: portValue, using: parameters)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let waiter = OneShotContinuation(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: waiter.resume(.success(()))
                case .failed(let error): waiter.resume(.failure(TransportError.connectionFailed(String(describing: error))))
                case .cancelled: waiter.resume(.failure(TransportError.cancelled))
                default: break
                }
            }
            connection.start(queue: queue)
        }

        return NWDatagramChannel(connection: connection)
    }

    /// A `DatagramChannelProvider` bound to `host` — the host part of `NWControlChannel`'s
    /// already-successful candidate, since UDP shares the same address (spec §11.3: "TCP / UDP
    /// port | 47800 / 47800", same host).
    public static func provider(host: String) -> DatagramChannelProvider {
        { udpPort in try await NWDatagramChannel.connect(host: host, udpPort: udpPort) }
    }

    public func send(_ datagram: Data) throws {
        connection.send(content: datagram, completion: .contentProcessed { _ in
            // Fire-and-forget per `DatagramChannel`'s synchronous contract; send failures show up
            // as probe/heartbeat loss (spec §3.5.8), not thrown errors.
        })
    }

    public func close() {
        connection.cancel()
        incomingContinuation.finish()
    }

    private func startReceiveLoop() {
        receiveNext()
    }

    private func receiveNext() {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.incomingContinuation.yield(data)
            }
            guard error == nil else {
                self.incomingContinuation.finish()
                return
            }
            self.receiveNext()
        }
    }
}
