// Transport/CLIControlChannel.swift
// The control-channel (TCP/TLS) `ControlChannel` implementation for `airmouse-cli` — the one package
// target allowed to import `Network` (CLAUDE.md, arch §3.1 rule 6). Mirrors the client TLS recipe in
// arch §7.2: TLS 1.3 minimum, a challenge block supplies the client identity on `CertificateRequest`,
// the verify block pins `fp == pinnedFingerprint` (spec §3.2.1 — from the pairing URL during `pair`,
// from the saved trust record afterwards, or a `--fingerprint` override), and SNI is never set because
// every host is addressed by IP literal (spec §3.3.2).
import AirMouseCore
import AirMouseCrypto
import AirMouseProtocol
import Dispatch
import Foundation
import Network
import Security

enum CLITransportError: Error, CustomStringConvertible {
    case invalidPort(Int)
    case connectionFailed(String)
    case notReady

    var description: String {
        switch self {
        case .invalidPort(let port): return "'\(port)' is not a valid TCP/UDP port"
        case .connectionFailed(let reason): return "connection failed: \(reason)"
        case .notReady: return "connection is not ready"
        }
    }
}

/// `ControlChannel` over `NWConnection` + TLS. `incoming` yields raw byte chunks exactly as
/// `NWConnection.receive` delivers them (arch: "the transport only moves bytes"); `ClientSession` owns
/// framing via its own `FrameDecoder`.
final class CLIControlChannel: ControlChannel, @unchecked Sendable {
    private let connection: NWConnection
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    let incoming: AsyncThrowingStream<Data, any Error>
    private let capturedPeerFingerprint = LockedBox<Fingerprint?>(nil)

    private init(connection: NWConnection) {
        self.connection = connection
        var continuation: AsyncThrowingStream<Data, any Error>.Continuation!
        self.incoming = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
    }

    /// Opens and waits for `.ready` on a TLS 1.3 control connection to `host:port`, presenting
    /// `identity` and accepting the peer only if its leaf certificate fingerprint equals
    /// `pinnedFingerprint`.
    static func connect(host: String, port: Int, identity: SecIdentity, pinnedFingerprint: Fingerprint) async throws -> CLIControlChannel {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(exactly: port) ?? 0) else {
            throw CLITransportError.invalidPort(port)
        }
        guard let secIdentity = sec_identity_create(identity) else {
            throw CLITransportError.connectionFailed("sec_identity_create failed")
        }

        let tlsOptions = NWProtocolTLS.Options()
        let secOptions = tlsOptions.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(secOptions, .TLSv13)
        let tlsQueue = DispatchQueue(label: "com.airmouse.cli.tls")
        sec_protocol_options_set_challenge_block(secOptions, { _, completeChallenge in
            completeChallenge(secIdentity)
        }, tlsQueue)

        let capturedFingerprint = LockedBox<Fingerprint?>(nil)
        sec_protocol_options_set_verify_block(secOptions, { _, trust, complete in
            guard let fingerprint = try? TLSPinning.fingerprint(from: trust) else {
                complete(false)
                return
            }
            capturedFingerprint.value = fingerprint
            complete(fingerprint == pinnedFingerprint)
        }, tlsQueue)

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        params.prohibitedInterfaceTypes = [.other]

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
        let channel = CLIControlChannel(connection: connection)
        channel.capturedPeerFingerprint.value = nil
        try await channel.waitUntilReady(capturing: capturedFingerprint, onto: channel.capturedPeerFingerprint)
        channel.startReceiveLoop()
        return channel
    }

    /// Bounds the handshake to `ProtocolConstants.addressPerCandidateTimeoutMs` (spec §3.3.2) rather
    /// than hanging forever — a closed/unreachable port on some networks never reaches `.failed`
    /// (Network.framework keeps retrying at the path level), so an explicit deadline is needed. On
    /// timeout, `connection.cancel()` drives the state machine to `.cancelled`, which resumes the same
    /// continuation exactly once (never left unresumed).
    private func waitUntilReady(capturing source: LockedBox<Fingerprint?>, onto destination: LockedBox<Fingerprint?>) async throws {
        let resumed = LockedBox<Bool>(false)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !resumed.value else { return }
                    resumed.value = true
                    destination.value = source.value
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
            let deadlineMs = ProtocolConstants.addressPerCandidateTimeoutMs
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(deadlineMs)) { [connection] in
                guard !resumed.value else { return }
                connection.cancel()
            }
        }
    }

    private func startReceiveLoop() {
        receiveNext()
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.continuation.yield(data)
            }
            if let error {
                self.continuation.finish(throwing: error)
                return
            }
            if isComplete {
                self.continuation.finish()
                return
            }
            self.receiveNext()
        }
    }

    func send(_ frame: Data) async throws {
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

    var peerFingerprint: Fingerprint? {
        get async { capturedPeerFingerprint.value }
    }

    /// spec §3.2.3: the TLS exporter for pairing-proof binding, label `EXPORTER-airmouse-pairing-v1`,
    /// empty context, 32 bytes (arch §7.2) — read from the connection's `NWProtocolTLS.Metadata` once
    /// `.ready`. Returns `nil` (the zero-exporter contingency, spec §3.2.3) if the platform does not
    /// expose `sec_protocol_metadata_create_secret` or no TLS metadata is available.
    func exporterSecret() async -> Data? {
        guard let tlsMetadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else {
            return nil
        }
        let secMetadata = tlsMetadata.securityProtocolMetadata
        let label = "EXPORTER-airmouse-pairing-v1"
        guard let rawSecret = label.withCString({ labelPointer in
            sec_protocol_metadata_create_secret(secMetadata, label.utf8.count, labelPointer, 32)
        }) else {
            return nil
        }
        let data = Data(rawSecret as DispatchData)
        return data.count == 32 ? data : nil
    }

    func close() async {
        continuation.finish()
        connection.cancel()
    }
}

/// A tiny `NSLock`-backed box so the TLS callback closures (which run on `tlsQueue`, not this class's
/// isolation) can hand a captured value back without data races — `Fingerprint` itself is `Sendable`
/// but plain `var` capture across those closures is not otherwise safe.
final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ initial: Value) { self.stored = initial }

    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}
