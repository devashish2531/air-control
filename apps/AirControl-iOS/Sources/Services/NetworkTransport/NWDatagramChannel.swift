// Services/NetworkTransport/NWDatagramChannel.swift
// Client-side motion (UDP) channel implementing `AirControlCore.DatagramChannel`, plus the
// `DatagramChannelProvider` factory `ClientSession` needs (spec §3.5 motion channel; arch's
// `ClientSession` doc comment: "the UDP port to connect to is only known once `helloAck.udpPort`
// arrives ... `datagramProvider` is the seam"). `.userInteractive` queue per this agent's brief —
// the motion path is the latency-sensitive one (spec §3.5.6/§3.5.7).

import Foundation
import Network
import AirControlCore

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

    /// Starts a UDP "connection" to `host:udpPort` and returns immediately — deliberately does
    /// **not** wait for `.ready`.
    ///
    /// This used to `await` a `CheckedContinuation` resolved from `.ready`, mirroring
    /// `NWControlChannel.connect`'s TCP handshake wait. That is wrong for UDP: there is no
    /// handshake, so `.ready` only means "a viable local path was found," and on real Wi-Fi that
    /// path validation can take seconds — or, per an on-device report (touches reaching
    /// `MotionPublisher`/`ClientSession.sendMotion` with zero datagrams ever observed at the
    /// helper), effectively never complete, even though the socket would have worked fine had data
    /// simply been sent on it. Since `datagramProvider` is awaited from `ClientSession.
    /// installSessionKey`, which gates `sessionKeyReply` and therefore `pair()`/`connect()`
    /// itself, blocking here could hang the whole session before the UI ever shows "Connected" —
    /// or, if `.ready` arrived late, silently delay every motion send behind it. Network.framework
    /// queues sends made before a connectionless path finishes validating and flushes them once it
    /// does, so starting the connection and handing back the channel right away is both safe and
    /// the documented idiom for this transport; `ProbeController` (via `ClientSession.sendProbe`)
    /// is what actually detects an unusable path now, by design, and drives TCP fallback within
    /// ~2 s (spec §3.5.8) if this path never pans out.
    public static func connect(host: String, udpPort: Int) async throws -> NWDatagramChannel {
        guard let portValue = NWEndpoint.Port(rawValue: UInt16(clamping: udpPort)) else {
            throw TransportError.invalidPort(udpPort)
        }
        let queue = DispatchQueue(label: "com.aircontrol.app.net.motion", qos: .userInteractive)
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = false // spec §3.1.1: "no AWDL" on either channel.

        let connection = NWConnection(host: NWEndpoint.Host(host), port: portValue, using: parameters)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Log.net.debug("motion UDP connection ready")
            case .waiting(let error):
                // Not swallowed: previously nothing observed this state at all once nobody was
                // still awaiting `.ready`, so a path that never recovers left no trace anywhere.
                Log.net.error("motion UDP connection .waiting: \(String(describing: error), privacy: .public)")
            case .failed(let error):
                Log.net.error("motion UDP connection .failed: \(String(describing: error), privacy: .public)")
            case .cancelled:
                break
            default:
                break
            }
        }
        connection.start(queue: queue)

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
