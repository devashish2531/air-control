// NWControlChannel — Network.framework implementation of `AirControlCore.ControlChannel` (spec
// §3.4.1 framing lives in AirControlCore; this only moves already-framed bytes over one accepted
// TLS/TCP `NWConnection`, spec §7.2's TLS configuration sample). Owned by the networking agent
// (assignment: "Services/HostServer/").
import AirControlCore
import AirControlCrypto
import Foundation
import Network
import Security
import os

/// Wraps one accepted `NWConnection` (already configured with TLS parameters and started by
/// `HostServer`) as an `AirControlCore.ControlChannel`. `incoming` yields raw received byte chunks —
/// `AirControlCore.HostSession` owns `FrameDecoder` and feeds these chunks into it itself (see that
/// type's `runReceiveLoop`); this channel does no framing of its own.
public actor NWControlChannel: ControlChannel {
    private let connection: NWConnection
    /// Cached after first successful extraction (spec §3.2.1's verify block already ran the exact
    /// same DER→SHA-256 computation to decide whether to accept the handshake at all — this is an
    /// independent, post-handshake re-derivation from the connection's own TLS metadata, per the
    /// assignment: "`peerFingerprint` (from `sec_protocol_metadata_copy_peer_public_key`/
    /// `sec_protocol_metadata_access_peer_certificate_chain` via `TLSPinning`)").
    private var cachedPeerFingerprint: Fingerprint?

    public nonisolated let incoming: AsyncThrowingStream<Data, any Error>
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    private var didStart = false
    private var isClosed = false
    private var isReady = false
    /// Resumed by `markReady()`/`finish(throwing:)` — see `waitUntilReady()`.
    private var readyWaiters: [CheckedContinuation<Bool, Never>] = []

    public init(connection: NWConnection) {
        self.connection = connection
        var cont: AsyncThrowingStream<Data, any Error>.Continuation!
        self.incoming = AsyncThrowingStream { cont = $0 }
        self.continuation = cont
    }

    /// Starts (if needed) the underlying connection on `queue` and begins the receive loop. Safe to
    /// call once; a second call is a no-op. `queue` should be the host's dedicated networking queue
    /// (spec §5.1.1: "networking on a dedicated `DispatchQueue(\"net\", qos: .userInteractive)`").
    public func start(on queue: DispatchQueue) {
        guard !didStart else { return }
        didStart = true
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { await self?.markReady() }
            case .failed(let error):
                Task { await self?.finish(throwing: error) }
            case .cancelled:
                Task { await self?.finish(throwing: nil) }
            default:
                break
            }
        }
        if connection.state == .setup {
            connection.start(queue: queue)
        }
        receiveNext()
    }

    /// Awaits the connection reaching `.ready` (TLS handshake, including client-cert verification,
    /// complete) — `true` — or terminating beforehand (`.failed`/`.cancelled`) — `false`. Callers
    /// that need `peerFingerprint` (spec §3.2.1's known/unknown peer classification, decided once at
    /// accept time by `HostServer.accept`/`SessionManager.acceptConnection`) must await this first:
    /// `start(on:)` only *begins* the async handshake, so `Network.framework` hasn't attached
    /// `NWProtocolTLS.Metadata` to the connection yet by the time `start(on:)` returns — reading
    /// `peerFingerprint` any earlier always sees `nil`, silently misclassifying every peer (even an
    /// already-trusted one reconnecting) as `.unknown`.
    public func waitUntilReady() async -> Bool {
        if isReady { return true }
        if isClosed { return false }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            readyWaiters.append(cont)
        }
    }

    private func markReady() {
        guard !isReady, !isClosed else { return }
        isReady = true
        let waiters = readyWaiters
        readyWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: true) }
    }

    private func receiveNext() {
        guard !isClosed else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            Task { await self?.handleReceive(data: data, isComplete: isComplete, error: error) }
        }
    }

    private func handleReceive(data: Data?, isComplete: Bool, error: NWError?) {
        guard !isClosed else { return }
        if let data, !data.isEmpty {
            continuation.yield(data)
        }
        if let error {
            continuation.finish(throwing: error)
            isClosed = true
            failReadyWaiters()
            return
        }
        if isComplete {
            continuation.finish()
            isClosed = true
            failReadyWaiters()
            return
        }
        receiveNext()
    }

    private func finish(throwing error: Error?) {
        guard !isClosed else { return }
        isClosed = true
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
        failReadyWaiters()
    }

    /// Resumes any `waitUntilReady()` callers still waiting with `false` — the connection closed
    /// (failed, cancelled, or the peer went away) before ever reaching `.ready`.
    private func failReadyWaiters() {
        let waiters = readyWaiters
        readyWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: false) }
    }

    // MARK: - ControlChannel

    public func send(_ frame: Data) async throws {
        guard !isClosed else { throw CancellationError() }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: frame, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            })
        }
    }

    public var peerFingerprint: Fingerprint? {
        get async {
            if let cachedPeerFingerprint { return cachedPeerFingerprint }
            let extracted = Self.extractPeerFingerprint(from: connection)
            cachedPeerFingerprint = extracted
            return extracted
        }
    }

    /// Extracts the peer's leaf certificate fingerprint from the connection's negotiated TLS
    /// metadata (spec §3.2.1: "chain length must be exactly 1"). Returns `nil` before the
    /// handshake completes, or if the platform can't produce a certificate chain here.
    private static func extractPeerFingerprint(from connection: NWConnection) -> Fingerprint? {
        guard let tlsMetadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else {
            return nil
        }
        let secMetadata = tlsMetadata.securityProtocolMetadata
        var chain: [SecCertificate] = []
        let accessible = sec_protocol_metadata_access_peer_certificate_chain(secMetadata) { certificate in
            chain.append(sec_certificate_copy_ref(certificate).takeRetainedValue())
        }
        guard accessible, chain.count == 1, let leaf = chain.first else { return nil }
        let der = SecCertificateCopyData(leaf) as Data
        return Fingerprint(certificateDER: der)
    }

    /// TLS exporter secret for channel binding (spec §3.2.3): `sec_protocol_metadata_create_secret`
    /// with label `"EXPORTER-aircontrol-pairing-v1"`, 32 bytes. Returns `nil` if TLS metadata isn't
    /// available yet or the platform doesn't support exporters — callers (per spec's contingency)
    /// fall back to 32 zero bytes and advertise `pair-binding-certs`.
    public func exporterSecret() async -> Data? {
        guard let tlsMetadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else {
            return nil
        }
        let secMetadata = tlsMetadata.securityProtocolMetadata
        let label = "EXPORTER-aircontrol-pairing-v1"
        guard let raw = label.withCString({ cLabel in
            sec_protocol_metadata_create_secret(secMetadata, label.utf8.count, cLabel, 32)
        }) else {
            return nil
        }
        let dispatchData = raw as DispatchData
        var bytes = [UInt8]()
        bytes.reserveCapacity(dispatchData.count)
        dispatchData.enumerateBytes { buffer, _, _ in bytes.append(contentsOf: buffer) }
        return Data(bytes)
    }

    public func close() async {
        guard !isClosed else { return }
        isClosed = true
        connection.cancel()
        continuation.finish()
        failReadyWaiters()
    }
}
