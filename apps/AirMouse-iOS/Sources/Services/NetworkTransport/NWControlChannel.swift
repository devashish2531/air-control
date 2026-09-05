// Services/NetworkTransport/NWControlChannel.swift
// Client-side control (TCP/TLS) channel implementing `AirMouseCore.ControlChannel` over
// `Network.framework` — spec §3.2.1 (TLS configuration / client verify block), §4.5 (Connection
// manager). This module is one of the few allowed to `import Network` (CLAUDE.md: "Only
// `airmouse-cli` and the two apps import Network.framework").
//
// `incoming` yields RAW received TCP byte chunks, *not* pre-decoded frames: reading
// `ClientSession.runReceiveLoop`/`handleIncomingControlData` (AirMouseCore) shows it owns its own
// `FrameDecoder` and calls `frameDecoder.feed(data)` on every chunk handed up through
// `control.incoming` — so this channel must not try to frame-align on the transport's behalf, it
// only forwards whatever `NWConnection.receive` hands back. `send(_:)` writes the caller's
// already-length-prefixed `FrameEncoder` output verbatim (spec §3.4.1).

import Dispatch
import Foundation
import Network
import Security
import AirMouseCore
import AirMouseCrypto
import AirMouseProtocol

/// Transport-level errors surfaced by this module's channels — distinct from `AirMouseCore`'s own
/// error types, which never see `Network` (arch §3.1).
public enum TransportError: Error, Sendable, Equatable {
    /// spec §4.5.5: `NWBrowser`/`NWConnection` surfaced a Local Network permission denial
    /// (`NWError.dns(kDNSServiceErr_PolicyDenied)` or `currentPath?.unsatisfiedReason == .localNetworkDenied`).
    case localNetworkDenied
    case connectionFailed(String)
    case timedOut
    case cancelled
    case invalidPort(Int)
}

/// A `CheckedContinuation<Void, Error>` that can be resumed exactly once from a `@Sendable`
/// `NWConnection` callback. Plain local functions capturing a `var` flag don't satisfy Swift 6
/// strict concurrency when handed to `Network.framework`'s `@Sendable` handler closures, so both
/// this file and `NWDatagramChannel` share this tiny reference-type box instead.
final class OneShotContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<Void, Error>

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    /// Resumes with `result` unless already resumed. Returns `true` iff this call was the one
    /// that resumed the continuation (so a losing timeout branch knows whether it actually needs
    /// to cancel anything, rather than tearing down a connection that already reached `.ready`).
    @discardableResult
    func resume(_ result: Result<Void, Error>) -> Bool {
        lock.lock()
        let already = didResume
        didResume = true
        lock.unlock()
        guard !already else { return false }
        switch result {
        case .success: continuation.resume()
        case .failure(let error): continuation.resume(throwing: error)
        }
        return true
    }
}

/// One TLS 1.3 control connection to a host's `_airmouse._tcp` endpoint, pinned to a known
/// fingerprint (spec §3.2.1's client verify block: "accept iff FP == pinned FP for this host —
/// from QR during pairing; from Keychain afterwards. Chain length must be exactly 1."). Server
/// Name Indication is never set (spec: "server-name indication disabled — no hostname
/// validation"); trust rests entirely on the pinned fingerprint.
public final class NWControlChannel: ControlChannel, @unchecked Sendable {
    private let connection: NWConnection
    private let sendQueue: DispatchQueue

    public let incoming: AsyncThrowingStream<Data, any Error>
    private let incomingContinuation: AsyncThrowingStream<Data, any Error>.Continuation

    /// The pinned fingerprint this connection was verified against. The verify block only lets
    /// the handshake reach `.ready` when the leaf's fingerprint equals this value (or, during
    /// discovery-less trust-on-first-use, is absent — see `connect(expectedHostFingerprint:)`),
    /// so this is exactly the peer's fingerprint once connected.
    public let peerFingerprint: Fingerprint?

    /// The literal IP this connection actually resolved to (from `currentPath?.remoteEndpoint`
    /// once `.ready`), whether the caller connected by literal address or by a live Bonjour
    /// endpoint — spec §4.5.4: "After a hostID has connected successfully, its resolved IP is
    /// appended to `lastKnownAddresses`". `nil` only if the path's remote endpoint is unavailable.
    public let resolvedHost: String?

    /// Captured once, right after the handshake completes (`connection.metadata(definition:)`).
    /// `nil` on a platform/path where the TLS exporter is unavailable (spec §3.2.3 contingency).
    private let exporterMetadata: sec_protocol_metadata_t?

    private init(
        connection: NWConnection,
        sendQueue: DispatchQueue,
        peerFingerprint: Fingerprint?,
        resolvedHost: String?,
        exporterMetadata: sec_protocol_metadata_t?
    ) {
        self.connection = connection
        self.sendQueue = sendQueue
        self.peerFingerprint = peerFingerprint
        self.resolvedHost = resolvedHost
        self.exporterMetadata = exporterMetadata
        var continuation: AsyncThrowingStream<Data, any Error>.Continuation!
        self.incoming = AsyncThrowingStream { continuation = $0 }
        self.incomingContinuation = continuation
        startReceiveLoop()
    }

    /// Opens one TLS control connection to `host:port`, pinned to `expectedHostFingerprint`.
    /// Resolves once the connection reaches `.ready`; throws `TransportError` — including
    /// `.localNetworkDenied` (spec §4.5.5) — if it fails, is cancelled, or exceeds `timeout`
    /// first (spec §3.3.2: "per-candidate timeout 4 s", `ProtocolConstants.addressPerCandidateTimeoutMs`).
    public static func connect(
        host: String,
        port: Int,
        clientIdentity: SecIdentity,
        expectedHostFingerprint: Fingerprint,
        timeout: TimeInterval = Double(ProtocolConstants.addressPerCandidateTimeoutMs) / 1000.0
    ) async throws -> NWControlChannel {
        guard let portValue = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            throw TransportError.invalidPort(port)
        }
        return try await connect(
            to: .hostPort(host: NWEndpoint.Host(host), port: portValue),
            clientIdentity: clientIdentity,
            expectedHostFingerprint: expectedHostFingerprint,
            timeout: timeout
        )
    }

    /// Same as `connect(host:port:...)` but takes a raw `NWEndpoint` directly — the seam
    /// `BonjourBrowser`'s live browse results use, since a Bonjour `.service(...)` endpoint lets
    /// `Network.framework` resolve and connect in one step without this module ever needing to
    /// extract a literal IP out of a browse result (`AddressSelector`'s `Candidate` model, by
    /// contrast, is for the *literal* address candidates — `lastKnownAddresses`/`qrAddresses` —
    /// spec §3.3.2's other two tiers).
    public static func connect(
        to endpoint: NWEndpoint,
        clientIdentity: SecIdentity,
        expectedHostFingerprint: Fingerprint,
        timeout: TimeInterval = Double(ProtocolConstants.addressPerCandidateTimeoutMs) / 1000.0
    ) async throws -> NWControlChannel {
        let queue = DispatchQueue(label: "com.airmouse.app.net.control")
        let tlsOptions = NWProtocolTLS.Options()
        let secOptions = tlsOptions.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(secOptions, .TLSv13)
        sec_protocol_options_set_peer_authentication_required(secOptions, true)
        if let secIdentity = sec_identity_create(clientIdentity) {
            sec_protocol_options_set_local_identity(secOptions, secIdentity)
        }
        sec_protocol_options_set_verify_block(secOptions, { _, trust, complete in
            guard let fingerprint = try? TLSPinning.fingerprint(from: trust) else {
                complete(false)
                return
            }
            complete(fingerprint == expectedHostFingerprint)
        }, queue)

        let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        parameters.includePeerToPeer = false // spec §3.1.1: "no AWDL" on either channel.

        let connection = NWConnection(to: endpoint, using: parameters)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let waiter = OneShotContinuation(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    waiter.resume(.success(()))
                case .failed(let error):
                    waiter.resume(.failure(Self.mapConnectError(error, connection: connection)))
                case .waiting(let error):
                    if Self.isLocalNetworkDenied(error, connection: connection) {
                        waiter.resume(.failure(TransportError.localNetworkDenied))
                    }
                case .cancelled:
                    waiter.resume(.failure(TransportError.cancelled))
                case .setup, .preparing:
                    break
                @unknown default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                if waiter.resume(.failure(TransportError.timedOut)) {
                    connection.cancel()
                }
            }
        }

        // The verify block above only lets the handshake reach `.ready` when the leaf's
        // fingerprint equals `expectedHostFingerprint`, so that value *is* the peer fingerprint.
        var capturedExporterMetadata: sec_protocol_metadata_t?
        if let tlsMetadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata {
            capturedExporterMetadata = tlsMetadata.securityProtocolMetadata
        }
        var resolvedHost: String?
        if case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint {
            resolvedHost = Self.literalString(from: host)
        }

        return NWControlChannel(
            connection: connection,
            sendQueue: queue,
            peerFingerprint: expectedHostFingerprint,
            resolvedHost: resolvedHost,
            exporterMetadata: capturedExporterMetadata
        )
    }

    private static func literalString(from host: NWEndpoint.Host) -> String? {
        switch host {
        case .ipv4(let address): return "\(address)"
        case .ipv6(let address): return "\(address)"
        case .name(let name, _): return name
        @unknown default: return nil
        }
    }

    public func send(_ frame: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: frame, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// spec §3.2.3: `TLS-Exporter("EXPORTER-airmouse-pairing-v1", 32 B)`, empty context, via
    /// `sec_protocol_metadata_create_secret`. Returns `nil` if the platform can't produce one
    /// (contingency path: caller falls back to 32 zero bytes and advertises `"pair-binding-certs"`).
    public func exporterSecret() async -> Data? {
        guard let metadata = exporterMetadata else { return nil }
        let label = "EXPORTER-airmouse-pairing-v1"
        guard let rawSecret = label.withCString({ labelPointer in
            sec_protocol_metadata_create_secret(metadata, label.utf8.count, labelPointer, 32)
        }) else { return nil }
        let secretDispatchData = rawSecret as DispatchData
        var data = Data(count: secretDispatchData.count)
        data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            secretDispatchData.copyBytes(to: buffer, count: secretDispatchData.count)
        }
        return data
    }

    public func close() async {
        connection.cancel()
        incomingContinuation.finish()
    }

    private func startReceiveLoop() {
        receiveNext()
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.incomingContinuation.yield(data)
            }
            if let error {
                self.incomingContinuation.finish(throwing: Self.mapConnectError(error, connection: self.connection))
                return
            }
            if isComplete {
                self.incomingContinuation.finish()
                return
            }
            self.receiveNext()
        }
    }

    private static func isLocalNetworkDenied(_ error: NWError, connection: NWConnection) -> Bool {
        if case .dns(let code) = error, code == -65570 { return true } // kDNSServiceErr_PolicyDenied
        if connection.currentPath?.unsatisfiedReason == .localNetworkDenied { return true }
        return false
    }

    private static func mapConnectError(_ error: NWError, connection: NWConnection) -> Error {
        if isLocalNetworkDenied(error, connection: connection) { return TransportError.localNetworkDenied }
        return TransportError.connectionFailed(String(describing: error))
    }
}
