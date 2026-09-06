import Foundation
import AirControlCrypto
@testable import AirControlCore

/// A two-ended, in-memory `ControlChannel` for the loopback tests: `send` on one end delivers
/// directly to the other end's `incoming` stream, simulating an already-authenticated TLS
/// connection (peer fingerprint / exporter secret are supplied at construction, standing in for
/// what a real TLS handshake would expose).
actor InMemoryControlChannel: ControlChannel {
    private var continuation: AsyncThrowingStream<Data, any Error>.Continuation!
    nonisolated let incoming: AsyncThrowingStream<Data, any Error>
    private weak var peer: InMemoryControlChannel?
    private let fixedPeerFingerprint: Fingerprint?
    private let fixedExporterSecret: Data?
    private var closed = false

    init(peerFingerprint: Fingerprint?, exporterSecret: Data?) {
        var continuation: AsyncThrowingStream<Data, any Error>.Continuation!
        self.incoming = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
        self.fixedPeerFingerprint = peerFingerprint
        self.fixedExporterSecret = exporterSecret
    }

    func attach(peer: InMemoryControlChannel) {
        self.peer = peer
    }

    func send(_ frame: Data) async throws {
        guard !closed else { throw CoreError.channelClosed }
        guard let peer else { return }
        await peer.deliver(frame)
    }

    private func deliver(_ frame: Data) {
        guard !closed else { return }
        continuation.yield(frame)
    }

    var peerFingerprint: Fingerprint? { fixedPeerFingerprint }

    func exporterSecret() async -> Data? { fixedExporterSecret }

    func close() async {
        guard !closed else { return }
        closed = true
        continuation.finish()
    }
}

/// A two-ended, in-memory `DatagramChannel` with an optional per-direction drop predicate, for the
/// UDP-blackhole fallback test.
final class InMemoryDatagramChannel: DatagramChannel, @unchecked Sendable {
    private let continuation: AsyncStream<Data>.Continuation
    let incoming: AsyncStream<Data>
    private let lock = NSLock()
    private weak var peer: InMemoryDatagramChannel?
    private var isClosed = false
    /// When this returns `true`, an outgoing `send` is silently dropped (simulating a blocked
    /// router, spec §3.5.8's "UDP-blocked" scenario). Mutate only via `setDrop(_:)`.
    private var shouldDrop: @Sendable () -> Bool
    /// Test-only tap: called with every datagram this end attempts to send, whether or not it is
    /// then dropped — lets a test capture raw sealed datagrams (e.g. to replay one, or to parse
    /// out header counters and assert monotonicity) without a second consumer of `incoming`.
    private var onSend: (@Sendable (Data) -> Void)?

    init(shouldDrop: @escaping @Sendable () -> Bool = { false }) {
        var continuation: AsyncStream<Data>.Continuation!
        self.incoming = AsyncStream { continuation = $0 }
        self.continuation = continuation
        self.shouldDrop = shouldDrop
    }

    func attach(peer: InMemoryDatagramChannel) {
        lock.lock()
        self.peer = peer
        lock.unlock()
    }

    func setDrop(_ predicate: @escaping @Sendable () -> Bool) {
        lock.lock()
        shouldDrop = predicate
        lock.unlock()
    }

    func setOnSend(_ handler: @escaping @Sendable (Data) -> Void) {
        lock.lock()
        onSend = handler
        lock.unlock()
    }

    func send(_ datagram: Data) throws {
        lock.lock()
        let closedNow = isClosed
        let drop = shouldDrop()
        let target = peer
        let handler = onSend
        lock.unlock()
        guard !closedNow else { throw CoreError.channelClosed }
        handler?(datagram)
        guard !drop, let target else { return }
        target.deliver(datagram)
    }

    /// Test-only: injects a raw datagram as if it had been sent by the peer (e.g. to replay a
    /// previously captured datagram at the exact same header/counter).
    func injectIncoming(_ datagram: Data) {
        deliver(datagram)
    }

    private func deliver(_ datagram: Data) {
        lock.lock()
        let closedNow = isClosed
        lock.unlock()
        guard !closedNow else { return }
        continuation.yield(datagram)
    }

    func close() {
        lock.lock()
        guard !isClosed else { lock.unlock(); return }
        isClosed = true
        lock.unlock()
        continuation.finish()
    }
}

enum InMemoryTransportPair {
    /// Builds a connected control-channel pair, `(client, host)`, whose `peerFingerprint`/
    /// `exporterSecret` mimic what a completed TLS handshake would expose to each side.
    static func makeControlPair(
        clientFingerprint: Fingerprint,
        hostFingerprint: Fingerprint,
        sharedExporterSecret: Data?
    ) async -> (client: InMemoryControlChannel, host: InMemoryControlChannel) {
        let client = InMemoryControlChannel(peerFingerprint: hostFingerprint, exporterSecret: sharedExporterSecret)
        let host = InMemoryControlChannel(peerFingerprint: clientFingerprint, exporterSecret: sharedExporterSecret)
        await client.attach(peer: host)
        await host.attach(peer: client)
        return (client, host)
    }

    /// Builds a connected datagram-channel pair, `(client, host)`.
    static func makeDatagramPair(
        clientToHostDrop: @escaping @Sendable () -> Bool = { false },
        hostToClientDrop: @escaping @Sendable () -> Bool = { false }
    ) -> (client: InMemoryDatagramChannel, host: InMemoryDatagramChannel) {
        let client = InMemoryDatagramChannel(shouldDrop: clientToHostDrop)
        let host = InMemoryDatagramChannel(shouldDrop: hostToClientDrop)
        client.attach(peer: host)
        host.attach(peer: client)
        return (client, host)
    }
}

/// A stub `Fingerprint` for tests that don't exercise real certificate parsing.
func stubFingerprint(_ byte: UInt8) -> Fingerprint {
    Fingerprint(bytes: [UInt8](repeating: byte, count: Fingerprint.byteCount))!
}
