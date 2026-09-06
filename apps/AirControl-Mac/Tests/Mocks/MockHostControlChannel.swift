// MockHostControlChannel — an in-memory `AirControlCore.ControlChannel` pair for testing
// `SessionManager`/`HostSession` end-to-end without any real socket, TLS, or Keychain access.
// Owned by the networking agent (assignment: "Tests/Mocks/MockHost*.swift").
@testable import Air_Control
import AirControlCore
import AirControlCrypto
import AirControlProtocol
import Foundation
import os

/// One in-memory `ControlChannel`. Construct a connected pair with `MockHostControlChannel.pair()`:
/// each side's `send(_:)` feeds the other's `incoming` (already-framed bytes, exactly the contract
/// `AirControlCore.HostSession`/`ClientSession` expect — see `NWControlChannel`'s doc comment).
public final class MockHostControlChannel: ControlChannel, @unchecked Sendable {
    private struct State {
        var peerContinuation: AsyncThrowingStream<Data, any Error>.Continuation?
        var isClosed = false
        var sentFrames: [Data] = []
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Every frame this side sent (i.e. what the peer received), for assertions.
    public var sentFrames: [Data] { state.withLock { $0.sentFrames } }

    public var fingerprintOverride: Fingerprint?
    public var exporterOverride: Data?

    public nonisolated let incoming: AsyncThrowingStream<Data, any Error>
    private let ownContinuation: AsyncThrowingStream<Data, any Error>.Continuation

    private init() {
        var cont: AsyncThrowingStream<Data, any Error>.Continuation!
        self.incoming = AsyncThrowingStream { cont = $0 }
        self.ownContinuation = cont
    }

    /// Builds two connected ends. `hostSeesPeerFingerprint`/`clientSeesPeerFingerprint` are what
    /// each side reports as its peer's fingerprint (mirroring what the verify block would have
    /// extracted).
    public static func pair(hostSeesPeerFingerprint: Fingerprint?, clientSeesPeerFingerprint: Fingerprint?) -> (host: MockHostControlChannel, client: MockHostControlChannel) {
        let host = MockHostControlChannel()
        let client = MockHostControlChannel()
        host.state.withLock { $0.peerContinuation = client.ownContinuation }
        client.state.withLock { $0.peerContinuation = host.ownContinuation }
        host.fingerprintOverride = hostSeesPeerFingerprint
        client.fingerprintOverride = clientSeesPeerFingerprint
        return (host, client)
    }

    public func send(_ frame: Data) async throws {
        let (closed, peer) = state.withLock { s -> (Bool, AsyncThrowingStream<Data, any Error>.Continuation?) in
            s.sentFrames.append(frame)
            return (s.isClosed, s.peerContinuation)
        }
        guard !closed else { throw CancellationError() }
        peer?.yield(frame)
    }

    public var peerFingerprint: Fingerprint? {
        get async { fingerprintOverride }
    }

    public func exporterSecret() async -> Data? { exporterOverride }

    public func close() async {
        let peer = state.withLock { s -> AsyncThrowingStream<Data, any Error>.Continuation? in
            guard !s.isClosed else { return nil }
            s.isClosed = true
            return s.peerContinuation
        }
        ownContinuation.finish()
        peer?.finish()
    }
}
