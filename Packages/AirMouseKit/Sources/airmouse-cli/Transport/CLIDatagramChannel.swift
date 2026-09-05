// Transport/CLIDatagramChannel.swift
// The motion (UDP) `DatagramChannel` implementation for `airmouse-cli`. `ClientSession` supplies the
// `udpPort` from `helloAck` lazily via a `DatagramChannelProvider` closure (see
// `Transport/ControlChannel.swift`'s doc comment) — this type is what that closure builds.
import AirMouseCore
import Dispatch
import Foundation
import Network

/// `DatagramChannel` over a UDP `NWConnection`. `send` is best-effort and synchronous per the
/// protocol (spec §3.5: motion has no delivery guarantee, no retry).
final class CLIDatagramChannel: DatagramChannel, @unchecked Sendable {
    private let connection: NWConnection
    private let continuation: AsyncStream<Data>.Continuation
    let incoming: AsyncStream<Data>

    private init(connection: NWConnection) {
        self.connection = connection
        var continuation: AsyncStream<Data>.Continuation!
        self.incoming = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    static func connect(host: String, port: Int) async throws -> CLIDatagramChannel {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(exactly: port) ?? 0) else {
            throw CLITransportError.invalidPort(port)
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .udp)
        let channel = CLIDatagramChannel(connection: connection)
        try await channel.waitUntilReady()
        channel.startReceiveLoop()
        return channel
    }

    /// UDP has no handshake, so `.ready` normally arrives almost immediately regardless of whether
    /// the peer is reachable — but bounds it anyway (see `CLIControlChannel`'s identical guard) so a
    /// pathological path never hangs `ClientSession`'s `datagramProvider`.
    private func waitUntilReady() async throws {
        let resumed = LockedBox<Bool>(false)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !resumed.value else { return }
                    resumed.value = true
                    continuation.resume()
                case .failed(let error):
                    guard !resumed.value else { return }
                    resumed.value = true
                    continuation.resume(throwing: CLITransportError.connectionFailed(String(describing: error)))
                case .cancelled:
                    guard !resumed.value else { return }
                    resumed.value = true
                    continuation.resume(throwing: CLITransportError.connectionFailed("timed out or cancelled before ready"))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .seconds(4)) { [connection] in
                guard !resumed.value else { return }
                connection.cancel()
            }
        }
    }

    private func startReceiveLoop() {
        receiveNext()
    }

    private func receiveNext() {
        connection.receiveMessage { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.continuation.yield(data)
            }
            if error != nil {
                self.continuation.finish()
                return
            }
            if isComplete, self.connection.state == .cancelled {
                self.continuation.finish()
                return
            }
            self.receiveNext()
        }
    }

    func send(_ datagram: Data) throws {
        connection.send(content: datagram, completion: .contentProcessed { _ in })
    }

    func close() {
        continuation.finish()
        connection.cancel()
    }
}
