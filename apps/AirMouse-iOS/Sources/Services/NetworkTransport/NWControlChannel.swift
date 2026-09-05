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
///
/// Still used by `NWDatagramChannel` (the UDP motion channel has no TLS handshake to classify, so
/// its coarser cases are all it needs). `NWControlChannel.connect` itself now throws the far more
/// precise `TransportFailure` below — see that type's doc comment for why the coarse cases here
/// were no longer enough to drive correct UX/diagnostics for the control channel.
public enum TransportError: Error, Sendable, Equatable {
    /// spec §4.5.5: `NWBrowser`/`NWConnection` surfaced a Local Network permission denial
    /// (`NWError.dns(kDNSServiceErr_PolicyDenied)` or `currentPath?.unsatisfiedReason == .localNetworkDenied`).
    case localNetworkDenied
    case connectionFailed(String)
    /// The TLS handshake itself failed — either the peer's verify block rejected our identity, or
    /// (client side) our own verify block rejected the peer's fingerprint (spec §9 "TLS handshake
    /// failed / fingerprint mismatch"). Distinct from `.connectionFailed` so callers can tell "we
    /// never reached a TLS peer" apart from "we reached one, but couldn't trust it".
    case tlsHandshakeFailed(String)
    case timedOut
    case cancelled
    case invalidPort(Int)
}

/// Precise classification of why one TLS control-channel connect attempt didn't reach `.ready` —
/// the UX/diagnostics fix this type exists for: three failure modes that all used to collapse into
/// the same "Couldn't reach"/"timed out" copy even though they need completely different user
/// guidance (verified against a real macOS + iOS pair):
///
///  1. The Mac refuses an untrusted phone (its pairing window is closed): the Mac's own verify
///     block rejects our client certificate and sends a fatal TLS alert. *Our* verify block (which
///     only ever judges the Mac's certificate) still accepted the Mac fine — the failure arrives as
///     `.failed(NWError.tls(status))` with no local pin rejection on our side → `.tlsAlertFromPeer`.
///  2. Our own client identity (a Secure Enclave key) can't sign the TLS transcript: the Mac's
///     certificate *was* accepted by our verify block, but the handshake then stalls forever (no
///     alert ever arrives) until our own per-candidate watchdog gives up → `.clientIdentityFailure`.
///  3. A stale trust record (the Mac's identity was regenerated): our own verify block sees the
///     new certificate, computes its fingerprint, and rejects it because it doesn't match the
///     pinned value → `.peerCertificateMismatch`, decided *before* looking at the underlying
///     `NWError` at all, since our own rejection also happens to surface as `NWError.tls`.
///
/// `HandshakeProgress` is what lets `NWControlChannel.connect` tell these three apart from outside
/// the handshake: it records whether our verify block ever ran, and whether it accepted the peer.
public enum TransportFailure: Error, Sendable, Equatable {
    /// TCP connect refused/timed out/host unreachable — a definitive network-level answer arrived
    /// (`.failed`) before our own verify block ever ran, i.e. before any TLS progress at all.
    case unreachable
    /// spec §4.5.5: Local Network permission denial.
    case localNetworkDenied
    /// `.failed` with `NWError.tls(status)`, and our own verify block either never ran or accepted
    /// the peer — the *peer* (Mac) is the one that rejected the handshake. `description` is a short
    /// human-readable rendering of the alert/OSStatus (never the raw certificate/keys).
    case tlsAlertFromPeer(description: String)
    /// Our own verify block rejected the peer's certificate: its fingerprint didn't match what was
    /// pinned for this host. `expected`/`actual` are `Fingerprint.shortLogPrefix` values (8 hex
    /// characters) — never a full fingerprint (spec §7.4 logging rule).
    case peerCertificateMismatch(expected: String, actual: String)
    /// Our own verify block accepted the peer, but the handshake still never reached `.ready` and
    /// our own per-candidate watchdog fired — i.e. *we* never produced a valid client response
    /// (most likely the local client identity's private key couldn't sign). `description` notes the
    /// candidate/timeout that gave up.
    case clientIdentityFailure(description: String)
    /// The connection was cancelled (by the peer, or the transport) before ever reaching `.ready`,
    /// without an explicit `.failed` error and before our own timeout fired.
    case closedBeforeReady
    /// Our own per-candidate watchdog fired with no signal at all — verify block never ran, no
    /// `.failed`, nothing. Distinct from `.unreachable` (which is a definitive OS-level answer) and
    /// from `.clientIdentityFailure` (which requires verify to have already accepted the peer).
    case timedOut
    case invalidPort(Int)
}

/// Tracks how far one `NWConnection`'s TLS handshake progressed — specifically, whether *our own*
/// verify block (validating the peer's certificate against the pinned fingerprint) ever ran, and
/// whether it accepted the peer. This is the signal `TransportFailure`'s classification is built
/// on: from outside the handshake, "the Mac rejected us" (1), "our client identity is stuck" (2),
/// and "we rejected the Mac" (3) all otherwise look identical (either a `.failed` with some
/// `NWError`, or nothing at all until a timeout).
final class HandshakeProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var invoked = false
    private var accepted = false
    private var actualFingerprintPrefix: String?

    func recordVerify(accepted isAccepted: Bool, actualFingerprintPrefix prefix: String?) {
        lock.lock()
        invoked = true
        accepted = isAccepted
        actualFingerprintPrefix = prefix
        lock.unlock()
    }

    func snapshot() -> (invoked: Bool, accepted: Bool, actualFingerprintPrefix: String?) {
        lock.lock()
        defer { lock.unlock() }
        return (invoked, accepted, actualFingerprintPrefix)
    }
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
            throw TransportFailure.invalidPort(port)
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
        let progress = HandshakeProgress()
        let tlsOptions = NWProtocolTLS.Options()
        let secOptions = tlsOptions.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(secOptions, .TLSv13)
        sec_protocol_options_set_peer_authentication_required(secOptions, true)
        if let secIdentity = sec_identity_create(clientIdentity) {
            sec_protocol_options_set_local_identity(secOptions, secIdentity)
        }
        sec_protocol_options_set_verify_block(secOptions, { _, trust, complete in
            guard let fingerprint = try? TLSPinning.fingerprint(from: trust) else {
                progress.recordVerify(accepted: false, actualFingerprintPrefix: nil)
                complete(false)
                return
            }
            let matches = fingerprint == expectedHostFingerprint
            progress.recordVerify(accepted: matches, actualFingerprintPrefix: fingerprint.shortLogPrefix)
            complete(matches)
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
                    let failure = Self.classifyConnectError(error, progress: progress, connection: connection, expectedHostFingerprint: expectedHostFingerprint)
                    Log.net.error("NWControlChannel connect .failed: \(String(describing: error), privacy: .public) -> \(String(describing: failure), privacy: .public)")
                    waiter.resume(.failure(failure))
                case .waiting(let error):
                    if Self.isLocalNetworkDenied(error, connection: connection) {
                        Log.net.error("NWControlChannel connect .waiting: local network access denied")
                        waiter.resume(.failure(TransportFailure.localNetworkDenied))
                    }
                case .cancelled:
                    // No-ops via `OneShotContinuation` unless nothing else has resolved this connect
                    // attempt yet — i.e. an unexpected close (peer/transport tore it down) rather than
                    // our own timeout-triggered `connection.cancel()` below.
                    if waiter.resume(.failure(TransportFailure.closedBeforeReady)) {
                        Log.net.error("NWControlChannel connect .cancelled before ready (unexpected)")
                    }
                case .setup, .preparing:
                    break
                @unknown default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                let failure = Self.classifyTimeout(progress: progress, timeout: timeout)
                Log.net.error("NWControlChannel connect timed out after \(timeout, privacy: .public)s -> \(String(describing: failure), privacy: .public)")
                if waiter.resume(.failure(failure)) {
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
                // Post-`.ready` (this loop only ever runs after a successful handshake): no
                // connect-time classification applies here (no verify-block progress to consult),
                // so this just distinguishes local-network revocation and a late TLS alert from a
                // generic "the connection is gone" — reusing `.unreachable` as the closest fit.
                let failure: TransportFailure
                if Self.isLocalNetworkDenied(error, connection: self.connection) {
                    failure = .localNetworkDenied
                } else if case .tls(let status) = error {
                    failure = .tlsAlertFromPeer(description: Self.describeTLSAlert(status))
                } else {
                    failure = .unreachable
                }
                Log.net.error("NWControlChannel receive loop error: \(String(describing: error), privacy: .public) -> \(String(describing: failure), privacy: .public)")
                self.incomingContinuation.finish(throwing: failure)
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

    /// Classifies a `.failed(error)` state update — see `TransportFailure`'s doc comment for the
    /// three scenarios this distinguishes. Order matters: a rejection by *our own* verify block
    /// (`progress.accepted == false`) must be checked before inspecting `error` at all, because
    /// that rejection also surfaces as `NWError.tls(...)` — indistinguishable from a peer-sent
    /// alert by the `NWError` alone.
    private static func classifyConnectError(
        _ error: NWError,
        progress: HandshakeProgress,
        connection: NWConnection,
        expectedHostFingerprint: Fingerprint
    ) -> TransportFailure {
        if isLocalNetworkDenied(error, connection: connection) { return .localNetworkDenied }
        let snapshot = progress.snapshot()
        if snapshot.invoked, !snapshot.accepted {
            return .peerCertificateMismatch(
                expected: expectedHostFingerprint.shortLogPrefix,
                actual: snapshot.actualFingerprintPrefix ?? "unknown"
            )
        }
        if case .tls(let status) = error {
            return .tlsAlertFromPeer(description: Self.describeTLSAlert(status))
        }
        return .unreachable
    }

    /// Classifies our own per-candidate watchdog firing with no `.failed`/`.ready` ever arriving.
    private static func classifyTimeout(progress: HandshakeProgress, timeout: TimeInterval) -> TransportFailure {
        let snapshot = progress.snapshot()
        if snapshot.invoked, snapshot.accepted {
            // The peer's certificate was already accepted, so TLS reached the point where *we*
            // must respond with our own client certificate/signature — the only thing left to
            // stall on is our own client identity (e.g. a Secure Enclave key that can't sign).
            return .clientIdentityFailure(description: "client identity did not complete the handshake within \(timeout)s after the peer's certificate was accepted")
        }
        return .timedOut
    }

    /// SecureTransport alert/OSStatus codes that mean "the peer rejected our certificate" — spelled
    /// out numerically (rather than via the `errSSLPeer*` symbols) because those symbols live in the
    /// deprecated SecureTransport API surface and trip `-Wdeprecated-declarations` under this
    /// project's `AIRMOUSE_WARNINGS_AS_ERRORS`. Values per `<Security/SecureTransport.h>`.
    private static let peerCertificateRejectionStatuses: Set<OSStatus> = [
        -9807, // errSSLXCertChainInvalid
        -9808, // errSSLBadCert
        -9826, // errSSLPeerBadCert
        -9827, // errSSLPeerUnsupportedCert
        -9828, // errSSLPeerCertRevoked
        -9829, // errSSLPeerCertExpired
        -9830, // errSSLPeerCertUnknown
        -9832, // errSSLPeerUnknownCA
        -9833, // errSSLPeerAccessDenied
    ]

    private static func describeTLSAlert(_ status: OSStatus) -> String {
        if peerCertificateRejectionStatuses.contains(status) {
            return "peer refused our certificate (status \(status))"
        }
        return "TLS alert from peer (status \(status))"
    }
}
