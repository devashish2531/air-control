// IntegrationTests/LoopbackClientTransport.swift
// A minimal `ControlChannel`/`DatagramChannel` pair over `Network.framework`, self-contained inside
// this test target so `AirControlHelperIntegrationTests` does not depend on `aircontrol-cli` (a separate
// SwiftPM executable target this Xcode project does not, and should not, link against). Deliberately
// smaller than `aircontrol-cli`'s `CLIControlChannel`/`CLIDatagramChannel` (Packages/AirControlKit/Sources/
// aircontrol-cli/Transport/) — same TLS recipe (arch §7.2: TLS 1.3, challenge block supplies the client
// identity, verify block pins `fp == pinnedFingerprint`, no SNI since every host here is 127.0.0.1),
// no persistence (a fresh ephemeral identity per test run is fine — the helper's `--loopback` mode
// treats every connection as first-time pairing anyway).
import AirControlCore
import AirControlCrypto
import Dispatch
import Foundation
import Network
import Security

enum LoopbackTransportError: Error, CustomStringConvertible {
    case invalidPort(Int)
    case connectionFailed(String)

    var description: String {
        switch self {
        case .invalidPort(let port): return "'\(port)' is not a valid port"
        case .connectionFailed(let reason): return "connection failed: \(reason)"
        }
    }
}

/// Small `NSLock`-backed box for handing a value captured on the TLS callback queue back to the
/// caller without a data race (mirrors `aircontrol-cli`'s identical helper).
final class LoopbackLockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ initial: Value) { stored = initial }
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}

final class LoopbackControlChannel: ControlChannel, @unchecked Sendable {
    private let connection: NWConnection
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    let incoming: AsyncThrowingStream<Data, any Error>
    private let capturedPeerFingerprint = LoopbackLockedBox<Fingerprint?>(nil)

    private init(connection: NWConnection) {
        self.connection = connection
        var continuation: AsyncThrowingStream<Data, any Error>.Continuation!
        self.incoming = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
    }

    static func connect(host: String, port: Int, identity: SecIdentity, pinnedFingerprint: Fingerprint) async throws -> LoopbackControlChannel {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(exactly: port) ?? 0) else {
            throw LoopbackTransportError.invalidPort(port)
        }
        guard let secIdentity = sec_identity_create(identity) else {
            throw LoopbackTransportError.connectionFailed("sec_identity_create failed")
        }

        let tlsOptions = NWProtocolTLS.Options()
        let secOptions = tlsOptions.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(secOptions, .TLSv13)
        let tlsQueue = DispatchQueue(label: "com.aircontrol.integrationtests.tls")
        sec_protocol_options_set_challenge_block(secOptions, { _, completeChallenge in
            completeChallenge(secIdentity)
        }, tlsQueue)

        let captured = LoopbackLockedBox<Fingerprint?>(nil)
        sec_protocol_options_set_verify_block(secOptions, { _, trust, complete in
            guard let fingerprint = try? TLSPinning.fingerprint(from: trust) else {
                complete(false)
                return
            }
            captured.value = fingerprint
            complete(fingerprint == pinnedFingerprint)
        }, tlsQueue)

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        params.requiredInterfaceType = .loopback

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
        let channel = LoopbackControlChannel(connection: connection)
        try await channel.waitUntilReady(capturing: captured, onto: channel.capturedPeerFingerprint)
        channel.receiveNext()
        return channel
    }

    private func waitUntilReady(capturing source: LoopbackLockedBox<Fingerprint?>, onto destination: LoopbackLockedBox<Fingerprint?>) async throws {
        let resumed = LoopbackLockedBox<Bool>(false)
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
                    continuation.resume(throwing: LoopbackTransportError.connectionFailed(String(describing: error)))
                case .cancelled:
                    guard !resumed.value else { return }
                    resumed.value = true
                    continuation.resume(throwing: LoopbackTransportError.connectionFailed("timed out or cancelled before ready"))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .seconds(5)) { [connection] in
                guard !resumed.value else { return }
                connection.cancel()
            }
        }
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
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    var peerFingerprint: Fingerprint? {
        get async { capturedPeerFingerprint.value }
    }

    func exporterSecret() async -> Data? {
        guard let tlsMetadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else {
            return nil
        }
        let secMetadata = tlsMetadata.securityProtocolMetadata
        let label = "EXPORTER-aircontrol-pairing-v1"
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

final class LoopbackDatagramChannel: DatagramChannel, @unchecked Sendable {
    private let connection: NWConnection
    private let continuation: AsyncStream<Data>.Continuation
    let incoming: AsyncStream<Data>

    private init(connection: NWConnection) {
        self.connection = connection
        var continuation: AsyncStream<Data>.Continuation!
        self.incoming = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    static func connect(host: String, port: Int) async throws -> LoopbackDatagramChannel {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(exactly: port) ?? 0) else {
            throw LoopbackTransportError.invalidPort(port)
        }
        let params = NWParameters.udp
        params.requiredInterfaceType = .loopback
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
        let channel = LoopbackDatagramChannel(connection: connection)
        try await channel.waitUntilReady()
        channel.receiveNext()
        return channel
    }

    private func waitUntilReady() async throws {
        let resumed = LoopbackLockedBox<Bool>(false)
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
                    continuation.resume(throwing: LoopbackTransportError.connectionFailed(String(describing: error)))
                case .cancelled:
                    guard !resumed.value else { return }
                    resumed.value = true
                    continuation.resume(throwing: LoopbackTransportError.connectionFailed("timed out or cancelled before ready"))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .seconds(5)) { [connection] in
                guard !resumed.value else { return }
                connection.cancel()
            }
        }
    }

    private func receiveNext() {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.continuation.yield(data)
            }
            if error != nil {
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
