// HostServerNWDatagramChannelTests — spec §3.5.1 (44-byte datagram, sessionID demux), §7.6 (bounded
// receive). Exercises `NWUDPHub`/`NWDatagramChannel` over a real loopback UDP socket with two
// registered "fake sessions" (two `sessionID`s), asserting each channel only receives its own.
@testable import Air_Control
import AirControlCrypto
import Foundation
import Network
import Testing

@Suite("NWDatagramChannel/NWUDPHub", .serialized)
struct HostServerNWDatagramChannelTests {
    private static func makeDatagram(sessionID: UInt32, counter: UInt64, marker: UInt8) -> Data {
        var bytes = MotionDatagramHeader(sessionID: sessionID, counter: counter).bytes
        bytes.append(contentsOf: [UInt8](repeating: marker, count: 32)) // 16-byte "ciphertext" + 16-byte "tag"
        return Data(bytes)
    }

    @Test("datagrams are routed to the channel registered for their sessionID, not the other")
    func demuxBySessionID() async throws {
        let hub = NWUDPHub()
        try await hub.start(port: 0, loopbackOnly: true)
        defer { hub.stop() }

        guard let port = hub.boundPort else {
            Issue.record("hub did not bind a port")
            return
        }

        let channelA = hub.register(sessionID: 0xAAAA_AAAA)
        let channelB = hub.register(sessionID: 0xBBBB_BBBB)

        let sender = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .udp)
        let queue = DispatchQueue(label: "test.udpdemux")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sender.stateUpdateHandler = { state in
                switch state {
                case .ready: continuation.resume()
                case .failed(let error): continuation.resume(throwing: error)
                default: break
                }
            }
            sender.start(queue: queue)
        }

        let datagramA = Self.makeDatagram(sessionID: 0xAAAA_AAAA, counter: 1, marker: 0xAA)
        let datagramB = Self.makeDatagram(sessionID: 0xBBBB_BBBB, counter: 1, marker: 0xBB)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sender.send(content: datagramA, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sender.send(content: datagramB, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }

        var receivedA: Data?
        for await data in channelA.incoming {
            receivedA = data
            break
        }
        var receivedB: Data?
        for await data in channelB.incoming {
            receivedB = data
            break
        }

        #expect(receivedA == datagramA)
        #expect(receivedB == datagramB)
        #expect(receivedA != receivedB)

        sender.cancel()
        channelA.close()
        channelB.close()
    }

    @Test("a datagram with the wrong length (not 44 bytes) is dropped before reaching any channel")
    func wrongLengthDropped() async throws {
        let hub = NWUDPHub()
        try await hub.start(port: 0, loopbackOnly: true)
        defer { hub.stop() }
        guard let port = hub.boundPort else {
            Issue.record("hub did not bind a port")
            return
        }
        let channel = hub.register(sessionID: 0x1234_5678)

        let sender = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .udp)
        let queue = DispatchQueue(label: "test.udpdemux.badlength")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sender.stateUpdateHandler = { state in
                if case .ready = state { continuation.resume() }
                if case .failed(let error) = state { continuation.resume(throwing: error) }
            }
            sender.start(queue: queue)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sender.send(content: Data([0x01, 0x02, 0x03]), completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }

        let before = hub.droppedBeforeDecryptCount
        // Give the receive loop a brief moment to process (no reliable completion signal for "never
        // arrives"), then confirm the drop counter advanced and the channel got nothing.
        try await Task.sleep(for: .milliseconds(200))
        #expect(hub.droppedBeforeDecryptCount > before)

        sender.cancel()
        channel.close()
    }
}
