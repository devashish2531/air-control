import Testing
import Foundation
@testable import AirMouseCore
import AirMouseProtocol
import AirMouseCrypto
import AirMouseFilters

/// Thrown when a test body races past `withTestTimeout`'s deadline — turns a would-be-hung test
/// into a fast, clearly-labeled failure instead of blocking the whole suite.
struct TestTimedOutError: Error, CustomStringConvertible {
    var description: String { "test body did not complete within the timeout" }
}

/// Races `operation` against a `seconds`-long timer; if the timer fires first, cancels
/// `operation`'s task and throws `TestTimedOutError` instead of letting a genuine deadlock hang
/// the whole suite forever.
func withTestTimeout<T: Sendable>(
    seconds: Double,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TestTimedOutError()
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw TestTimedOutError()
        }
        return result
    }
}

/// End-to-end loopback tests: an in-memory `ControlChannel`/`DatagramChannel` pair (spec-shaped,
/// with optional datagram drop) driving a real `ClientSession` against a real `HostSession` —
/// pairing → session key → motion → click → heartbeat → UDP blackhole → fallback → recovery, plus
/// version mismatch. No `Network.framework` anywhere (per this module's own rule).
@Suite struct E2ELoopbackTests {
    struct Fixture {
        let client: ClientSession
        let host: HostSession
        let clientDatagram: InMemoryDatagramChannel
        let clock: ManualClock
        let hostFingerprint: Fingerprint
        let clientFingerprint: Fingerprint
        let hostID: Data
        let pairingURL: PairingURL
    }

    /// Builds a paired client/host with the control and datagram channels already wired, `hello →
    /// pairChallenge → pairProof → pairConfirm → helloAck → sessionKey` not yet started.
    static func makeFixture() async throws -> Fixture {
        let clock = ManualClock(start: 1_700_000_000)
        let hostFingerprint = stubFingerprint(0xAA)
        let clientFingerprint = stubFingerprint(0xBB)
        let sharedExporter = Data(repeating: 0xCC, count: 32)

        let (clientControl, hostControl) = await InMemoryTransportPair.makeControlPair(
            clientFingerprint: clientFingerprint,
            hostFingerprint: hostFingerprint,
            sharedExporterSecret: sharedExporter
        )
        let (clientDatagram, hostDatagram) = InMemoryTransportPair.makeDatagramPair()

        var window = PairingWindow()
        let secret = try window.open(now: Date(timeIntervalSince1970: clock.now()))
        let hostID = Data(repeating: 0x01, count: 16)

        let identity = HostSession.HostIdentity(
            hostID: hostID,
            name: "Test Mac",
            model: "Mac15,6",
            os: "macOS 15.0",
            helperVersion: "1.0",
            fingerprint: hostFingerprint
        )
        let hostState = HostState(
            paused: false,
            accessibility: true,
            naturalScroll: false,
            displays: [],
            inputSource: InputSource(id: "com.apple.keylayout.US", ansi: true),
            scriptsAllowed: false,
            sessionCount: 0
        )
        let host = HostSession(
            control: hostControl,
            clock: clock,
            identity: identity,
            peerKnowledge: .unknown,
            pairingWindow: window,
            hostState: hostState,
            udpPort: 47800
        )
        await host.start()
        await host.attachDatagramChannel(hostDatagram)

        let device = Hello.Device(name: "Test iPhone", model: "iPhone16,1", os: "iOS 18.0", app: "1.0")
        let client = ClientSession(
            control: clientControl,
            datagramProvider: { _ in clientDatagram },
            clock: clock,
            localFingerprint: clientFingerprint,
            device: device
        )

        let pairingURL = try PairingURL(
            version: ProtocolConstants.protocolVersion,
            hostID: hostID,
            hostName: "Test Mac",
            addresses: ["127.0.0.1"],
            tcpPort: 47800,
            fingerprint: Data(hostFingerprint.bytes),
            secret: Data(secret.bytes)
        )

        return Fixture(
            client: client,
            host: host,
            clientDatagram: clientDatagram,
            clock: clock,
            hostFingerprint: hostFingerprint,
            clientFingerprint: clientFingerprint,
            hostID: hostID,
            pairingURL: pairingURL
        )
    }

    /// Pulls events from `stream` until one matches `match`, ignoring everything else (bounded to
    /// avoid ever hanging a failing test forever).
    static func nextEvent<Event>(
        from iterator: inout AsyncStream<Event>.AsyncIterator,
        matching match: (Event) -> Bool,
        maxToSkip: Int = 50
    ) async -> Event? {
        for _ in 0..<maxToSkip {
            guard let event = await iterator.next() else { return nil }
            if match(event) { return event }
        }
        return nil
    }

    static func waitUntil(timeoutSeconds: Double = 2, condition: () async -> Bool) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // MARK: - Pairing → sessionKey

    @Test func pairingHandshakeEstablishesSessionKey() async throws {
        try await withTestTimeout(seconds: 20) {
        let fixture = try await Self.makeFixture()
        var hostEventIterator = fixture.host.events.makeAsyncIterator()

        let info = try await fixture.client.pair(url: fixture.pairingURL)
        #expect(info.protocolVersion == ProtocolConstants.protocolVersion)
        #expect(info.udpPort == 47800)

        let authenticated = await Self.nextEvent(from: &hostEventIterator) {
            if case .clientAuthenticated = $0 { return true }
            return false
        }
        #expect(authenticated != nil)

        let sessionID = await fixture.host.currentSessionID
        #expect(sessionID != nil)
        let hostState = await fixture.host.currentState
        #expect(hostState == .authenticated)
        }
    }

    @Test func pairingWithWrongProofFailsClientSide() async throws {
        try await withTestTimeout(seconds: 20) {
        let fixture = try await Self.makeFixture()
        // Tamper with the pairing URL's secret so the client computes a proof the host rejects.
        var tamperedBytes = Data(repeating: 0x01, count: 16)
        tamperedBytes[0] = 0xFF
        let badURL = try PairingURL(
            version: ProtocolConstants.protocolVersion,
            hostID: fixture.hostID,
            hostName: "Test Mac",
            addresses: ["127.0.0.1"],
            tcpPort: 47800,
            fingerprint: fixture.pairingURL.fingerprint,
            secret: tamperedBytes
        )
        await #expect(throws: (any Error).self) {
            _ = try await fixture.client.pair(url: badURL)
        }
        }
    }

    // MARK: - Motion: 200 datagrams, counter monotonicity, replay rejection

    @Test func twoHundredMotionDatagramsDeliveredWithMonotonicCounters() async throws {
        try await withTestTimeout(seconds: 20) {
        let fixture = try await Self.makeFixture()
        var hostEventIterator = fixture.host.events.makeAsyncIterator()
        _ = try await fixture.client.pair(url: fixture.pairingURL)
        _ = await Self.nextEvent(from: &hostEventIterator) {
            if case .clientAuthenticated = $0 { return true }
            return false
        }

        final class Capture: @unchecked Sendable {
            var datagrams: [Data] = []
        }
        let capture = Capture()
        fixture.clientDatagram.setOnSend { data in capture.datagrams.append(data) }

        for index in 0..<200 {
            let payload = MotionPayload(
                source: .touch,
                samples: 1,
                timestamp: UInt32(index),
                dx: 8,
                dy: 0,
                scrollX: 0,
                scrollY: 0
            )
            try await fixture.client.sendMotion(payload)
        }

        var delivered: [MotionDeltaEvent] = []
        while delivered.count < 200 {
            guard let event = await hostEventIterator.next() else { break }
            if case .motion(let motion) = event, motion.channel == .udp {
                delivered.append(motion)
            }
        }
        #expect(delivered.count == 200)
        #expect(delivered.allSatisfy { $0.shouldApply })

        // Counter monotonicity: every sealed datagram's header counter strictly increases.
        #expect(capture.datagrams.count == 200)
        let counters = capture.datagrams.compactMap { MotionCrypto.peekHeader(datagram: Array($0))?.counter }
        #expect(counters.count == 200)
        for index in 1..<counters.count {
            #expect(counters[index] > counters[index - 1])
        }

        // Replay rejection: resending the exact last datagram must be dropped silently (spec
        // §3.5.1/§3.5.4) rather than delivered as a new motion event. Proven deterministically
        // (no timing race): send the replay, then one fresh, distinguishable datagram; because
        // the channel and both actors preserve order, the *next* `.motion` event must be the
        // fresh one if — and only if — the replay produced no event of its own.
        try fixture.clientDatagram.send(capture.datagrams.last!)
        let freshPayload = MotionPayload(source: .touch, samples: 1, timestamp: 9999, dx: 1, dy: 1, scrollX: 0, scrollY: 0)
        try await fixture.client.sendMotion(freshPayload)

        var nextMotion: MotionDeltaEvent?
        while nextMotion == nil {
            guard let event = await hostEventIterator.next() else { break }
            if case .motion(let motion) = event, motion.channel == .udp {
                nextMotion = motion
            }
        }
        #expect(nextMotion?.payload.timestamp == 9999)
        }
    }

    // MARK: - Click round trip

    @Test func clickRoundTripsToHostEvent() async throws {
        try await withTestTimeout(seconds: 20) {
        let fixture = try await Self.makeFixture()
        var hostEventIterator = fixture.host.events.makeAsyncIterator()
        _ = try await fixture.client.pair(url: fixture.pairingURL)
        _ = await Self.nextEvent(from: &hostEventIterator) {
            if case .clientAuthenticated = $0 { return true }
            return false
        }

        let click = Click(button: .left, action: .tap, count: 1, modifiers: [])
        try await fixture.client.sendClick(click)

        let received = await Self.nextEvent(from: &hostEventIterator) {
            if case .click = $0 { return true }
            return false
        }
        guard case .click(let receivedClick) = received else {
            Issue.record("expected a click event")
            return
        }
        #expect(receivedClick == click)
        }
    }

    // MARK: - Heartbeat RTT

    @Test func heartbeatProducesRTTStats() async throws {
        try await withTestTimeout(seconds: 20) {
        let fixture = try await Self.makeFixture()
        var hostEventIterator = fixture.host.events.makeAsyncIterator()
        _ = try await fixture.client.pair(url: fixture.pairingURL)
        _ = await Self.nextEvent(from: &hostEventIterator) {
            if case .clientAuthenticated = $0 { return true }
            return false
        }

        try await fixture.client.sendHeartbeat()
        await Self.waitUntil {
            await fixture.client.currentStats().rttP50 != nil
        }
        let stats = await fixture.client.currentStats()
        #expect(stats.rttP50 != nil)
        #expect(stats.rttP50! >= 0)
        }
    }

    // MARK: - UDP blackhole → fallback → recovery

    @Test func udpBlackholeTriggersFallbackThenRecovers() async throws {
        try await withTestTimeout(seconds: 20) {
        let fixture = try await Self.makeFixture()
        var hostEventIterator = fixture.host.events.makeAsyncIterator()
        _ = try await fixture.client.pair(url: fixture.pairingURL)
        _ = await Self.nextEvent(from: &hostEventIterator) {
            if case .clientAuthenticated = $0 { return true }
            return false
        }

        // Blackhole client -> host UDP.
        fixture.clientDatagram.setDrop { true }
        for _ in 0..<9 {
            try await fixture.client.sendProbe()
        }
        var stats = await fixture.client.currentStats()
        #expect(stats.isFallbackEngaged)

        // Motion now rides the TCP fallback path.
        for index in 0..<5 {
            let payload = MotionPayload(source: .touch, samples: 1, timestamp: UInt32(index), dx: 1, dy: 1, scrollX: 0, scrollY: 0)
            try await fixture.client.sendMotion(payload)
        }
        try await fixture.client.flushPendingMotionBatch()

        var tcpMotionCount = 0
        while tcpMotionCount < 5 {
            guard let event = await hostEventIterator.next() else { break }
            if case .motion(let motion) = event, motion.channel == .tcp {
                tcpMotionCount += 1
            }
        }
        #expect(tcpMotionCount == 5)

        // Network recovers: probes get through and are echoed; 5 consecutive answers recover.
        fixture.clientDatagram.setDrop { false }
        for _ in 0..<6 {
            try await fixture.client.sendProbe()
            // Give the echo a moment to round-trip before the next probe.
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        await Self.waitUntil(timeoutSeconds: 2) {
            await fixture.client.currentStats().isFallbackEngaged == false
        }
        stats = await fixture.client.currentStats()
        #expect(!stats.isFallbackEngaged)
        }
    }

    // MARK: - Version mismatch

    /// Drives a real `HostSession` with a hand-built `hello` whose `protocol` range shares nothing
    /// with this build's version (spec §3.4.4), and checks the wire-level response directly —
    /// `error { code: "protocol.versionMismatch", fatal: true }` — rather than going through
    /// `ClientSession` (which always advertises its own current, necessarily-compatible range).
    @Test func versionMismatchProducesFatalError() async throws {
        try await withTestTimeout(seconds: 20) {
        let clock = ManualClock(start: 1_700_000_000)
        let hostFingerprint = stubFingerprint(0xAA)
        let clientFingerprint = stubFingerprint(0xBB)
        let (clientControl, hostControl) = await InMemoryTransportPair.makeControlPair(
            clientFingerprint: clientFingerprint,
            hostFingerprint: hostFingerprint,
            sharedExporterSecret: nil
        )
        let identity = HostSession.HostIdentity(
            hostID: Data(repeating: 2, count: 16),
            name: "Test Mac",
            model: "Mac15,6",
            os: "macOS 15.0",
            helperVersion: "1.0",
            fingerprint: hostFingerprint
        )
        let hostState = HostState(
            paused: false, accessibility: true, naturalScroll: false, displays: [],
            inputSource: InputSource(id: "com.apple.keylayout.US", ansi: true),
            scriptsAllowed: false, sessionCount: 0
        )
        // Already-trusted reconnect path (known peer) so `hello` alone drives negotiation.
        let host = HostSession(
            control: hostControl, clock: clock, identity: identity, peerKnowledge: .known,
            pairingWindow: nil, hostState: hostState, udpPort: 47800
        )
        await host.start()

        #expect(ProtocolVersion.negotiate(clientMin: 99, clientMax: 100, hostMin: 1, hostMax: 1) == nil)

        let hello = Hello(
            protocol: .init(min: 99, max: 100),
            capabilities: [],
            device: .init(name: "Future Phone", model: "iPhoneFuture,1", os: "iOS 99", app: "9.0"),
            pairing: false,
            macroRevision: nil,
            displayHz: 60
        )
        let envelope = Envelope(v: 99, i: 0, message: .hello(hello))
        let body = try WireCoding.encodeEnvelope(envelope)
        let frame = try FrameEncoder.encode(kind: .json, body: body)
        try await clientControl.send(frame)

        var iterator = clientControl.incoming.makeAsyncIterator()
        guard let responseData = try await iterator.next() else {
            Issue.record("expected a response frame from the host")
            return
        }
        var responseDecoder = FrameDecoder()
        let frames = try responseDecoder.feed(responseData)
        guard let responseFrame = frames.first, responseFrame.kind == .json else {
            Issue.record("expected a JSON frame in the host's response")
            return
        }
        let responseEnvelope = try WireCoding.decodeEnvelope(responseFrame.body)
        guard case .error(let payload) = responseEnvelope.message else {
            Issue.record("expected an error message, got \(responseEnvelope.message)")
            return
        }
        #expect(payload.knownCode == .versionMismatch)
        #expect(payload.fatal)
        }
    }
}
