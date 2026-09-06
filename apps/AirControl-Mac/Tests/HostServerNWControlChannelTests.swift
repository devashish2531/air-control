// HostServerNWControlChannelTests — spec §3.4.1 (framing), §3.2.1/§7.2 (TLS 1.3 mTLS), §3.2.3 (TLS
// exporter). Exercises `NWControlChannel` over a *real* localhost TLS connection using two
// ephemeral (Keychain-free) identities, so it needs no code-signing/Keychain access in CI.
@testable import Air_Control
import AirControlCrypto
import AirControlProtocol
import Foundation
import Network
import Testing

@Suite("NWControlChannel", .serialized)
struct HostServerNWControlChannelTests {
    /// Spins up a loopback-only mTLS listener using `hostIdentity`, connects to it with
    /// `clientIdentity`, and returns both ends already `.ready` and wrapped as `NWControlChannel`.
    private static func makeConnectedPair(
        hostIdentity: GeneratedIdentity,
        clientIdentity: GeneratedIdentity
    ) async throws -> (host: NWControlChannel, client: NWControlChannel, listener: NWListener) {
        let queue = DispatchQueue(label: "test.nwcontrolchannel")

        func tlsOptions(local: GeneratedIdentity, isServer: Bool) throws -> NWProtocolTLS.Options {
            let options = NWProtocolTLS.Options()
            let sec = options.securityProtocolOptions
            sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv13)
            guard let secIdentityT = local.secIdentityT else { throw TestSetupError.noIdentity }
            if isServer {
                sec_protocol_options_set_local_identity(sec, secIdentityT)
                sec_protocol_options_set_peer_authentication_required(sec, true)
            } else {
                sec_protocol_options_set_challenge_block(sec, { _, complete in
                    complete(secIdentityT)
                }, queue)
            }
            // Test-only trust policy: accept any peer certificate (this suite tests framing/exporter
            // extraction, not `PinningPolicy` itself — that has its own coverage).
            sec_protocol_options_set_verify_block(sec, { _, _, complete in complete(true) }, queue)
            return options
        }

        let listenerParams = NWParameters(tls: try tlsOptions(local: hostIdentity, isServer: true))
        listenerParams.requiredInterfaceType = .loopback
        let listener = try NWListener(using: listenerParams, on: .any)

        let acceptedBox = ConnectionBox()
        // Must start the accepted connection immediately (not after waiting on the client) —
        // otherwise neither side's TLS handshake can progress: the client's `.ready` only fires
        // once the server side has actually processed the handshake, which requires this
        // connection to be started already.
        listener.newConnectionHandler = { connection in
            connection.stateUpdateHandler = { _ in }
            connection.start(queue: queue)
            Task { await acceptedBox.set(connection) }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: continuation.resume()
                case .failed(let error): continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
        guard let port = listener.port else { throw TestSetupError.noPort }

        let clientParams = NWParameters(tls: try tlsOptions(local: clientIdentity, isServer: false))
        clientParams.requiredInterfaceType = .loopback
        let clientConnection = NWConnection(host: "127.0.0.1", port: port, using: clientParams)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            clientConnection.stateUpdateHandler = { state in
                switch state {
                case .ready: continuation.resume()
                case .failed(let error): continuation.resume(throwing: error)
                default: break
                }
            }
            clientConnection.start(queue: queue)
        }

        // The client's `.ready` already implies the server side finished its half of the
        // handshake too; retrieve the (already-started) accepted connection and, since the two
        // sides' `.ready` transitions aren't perfectly synchronized, wait briefly for its own
        // `.ready` too — `sec_protocol_metadata_access_peer_certificate_chain` needs that before
        // it can return anything.
        var serverConnection: NWConnection?
        for _ in 0..<200 {
            if let connection = await acceptedBox.get() {
                serverConnection = connection
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard let serverConnection else { throw TestSetupError.noAcceptedConnection }
        for _ in 0..<200 {
            if serverConnection.state == .ready { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard serverConnection.state == .ready else { throw TestSetupError.noAcceptedConnection }

        let host = NWControlChannel(connection: serverConnection)
        let client = NWControlChannel(connection: clientConnection)
        await host.start(on: queue)
        await client.start(on: queue)
        return (host, client, listener)
    }

    private enum TestSetupError: Error { case noIdentity, noPort, noAcceptedConnection }

    private actor ConnectionBox {
        private var connection: NWConnection?
        func set(_ connection: NWConnection) { self.connection = connection }
        func get() -> NWConnection? { connection }
    }

    @Test("a frame sent by one side arrives byte-identical on the other, decodable by FrameDecoder")
    func framingRoundTrip() async throws {
        let hostIdentity = try IdentityFactory.makeEphemeralIdentity(commonName: "AirControl Host test")
        let clientIdentity = try IdentityFactory.makeEphemeralIdentity(commonName: "AirControl Client test")
        let (host, client, listener) = try await Self.makeConnectedPair(hostIdentity: hostIdentity, clientIdentity: clientIdentity)
        defer { listener.cancel() }

        let body = Data("hello over TLS".utf8)
        let frame = try FrameEncoder.encode(kind: .json, body: body)
        try await host.send(frame)

        var decoder = FrameDecoder()
        var decodedFrames: [Frame] = []
        for try await chunk in client.incoming {
            decodedFrames.append(contentsOf: try decoder.feed(chunk))
            if !decodedFrames.isEmpty { break }
        }
        #expect(decodedFrames.count == 1)
        #expect(decodedFrames.first?.kind == .json)
        #expect(decodedFrames.first?.body == body)

        await host.close()
        await client.close()
    }

    @Test("peerFingerprint on each side matches the other side's identity")
    func peerFingerprintExtraction() async throws {
        let hostIdentity = try IdentityFactory.makeEphemeralIdentity(commonName: "AirControl Host test 2")
        let clientIdentity = try IdentityFactory.makeEphemeralIdentity(commonName: "AirControl Client test 2")
        let (host, client, listener) = try await Self.makeConnectedPair(hostIdentity: hostIdentity, clientIdentity: clientIdentity)
        defer { listener.cancel() }

        let hostSeesPeer = await host.peerFingerprint
        let clientSeesPeer = await client.peerFingerprint
        #expect(hostSeesPeer == clientIdentity.fingerprint)
        #expect(clientSeesPeer == hostIdentity.fingerprint)

        await host.close()
        await client.close()
    }

    @Test("exporterSecret, if the platform provides one, is 32 bytes and agrees on both sides")
    func exporterSecretAgrees() async throws {
        let hostIdentity = try IdentityFactory.makeEphemeralIdentity(commonName: "AirControl Host test 3")
        let clientIdentity = try IdentityFactory.makeEphemeralIdentity(commonName: "AirControl Client test 3")
        let (host, client, listener) = try await Self.makeConnectedPair(hostIdentity: hostIdentity, clientIdentity: clientIdentity)
        defer { listener.cancel() }

        let hostExporter = await host.exporterSecret()
        let clientExporter = await client.exporterSecret()
        if let hostExporter, let clientExporter {
            #expect(hostExporter.count == 32)
            // spec §3.2.3: the exporter is the *same* 32 bytes on both ends of one TLS session
            // (used as shared channel-binding material for the pairing proof).
            #expect(hostExporter == clientExporter)
        }
        // If either side returned nil (platform doesn't expose the exporter here), that's the
        // spec §3.2.3 contingency path, not a test failure.

        await host.close()
        await client.close()
    }
}
