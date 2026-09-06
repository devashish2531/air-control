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

    // MARK: - Known peer, re-pairing (spec decision: HostSessionStateMachine's
    // `.tlsAccepted(.known)`/`.helloReceivedPairingTrue` case)

    /// Builds one connected host/client pair, parameterized by `peerKnowledge` and an optional
    /// pairing window — the two axes the re-pairing fix actually depends on (unlike
    /// `makeFixture()`, which is always an unknown-peer first-time pairing).
    private static func makeSessionPair(
        clock: ManualClock,
        hostFingerprint: Fingerprint,
        clientFingerprint: Fingerprint,
        hostID: Data,
        peerKnowledge: HostPeerKnowledge,
        pairingWindow: PairingWindow?,
        sharedExporterSecret: Data?
    ) async -> (host: HostSession, client: ClientSession) {
        let (clientControl, hostControl) = await InMemoryTransportPair.makeControlPair(
            clientFingerprint: clientFingerprint,
            hostFingerprint: hostFingerprint,
            sharedExporterSecret: sharedExporterSecret
        )
        let identity = HostSession.HostIdentity(
            hostID: hostID, name: "Test Mac", model: "Mac15,6", os: "macOS 15.0",
            helperVersion: "1.0", fingerprint: hostFingerprint
        )
        let hostState = HostState(
            paused: false, accessibility: true, naturalScroll: false, displays: [],
            inputSource: InputSource(id: "com.apple.keylayout.US", ansi: true),
            scriptsAllowed: false, sessionCount: 0
        )
        let host = HostSession(
            control: hostControl, clock: clock, identity: identity, peerKnowledge: peerKnowledge,
            pairingWindow: pairingWindow, hostState: hostState, udpPort: 47800
        )
        await host.start()
        let client = ClientSession(
            control: clientControl,
            datagramProvider: { _ in InMemoryDatagramChannel() },
            clock: clock,
            localFingerprint: clientFingerprint,
            device: Hello.Device(name: "Test iPhone", model: "iPhone16,1", os: "iOS 18.0", app: "1.0")
        )
        return (host, client)
    }

    /// Reproduces the reported bug's setup end to end: a device pairs, is forgotten by nothing (it
    /// stays trusted), and re-scans a fresh pairing QR later. Asserts both that re-pairing
    /// succeeds (rather than hanging until the host's watchdog closes the connection) and that a
    /// trust store driven the way `SessionManager.recordAuthenticated` drives it — add on first
    /// pairing, update (never a second `add`) on every later one — ends up with exactly one
    /// record for this client identity.
    @Test func rePairingATrustedClientSucceedsWithOneTrustStoreRecord() async throws {
        try await withTestTimeout(seconds: 20) {
        let trustStore = InMemoryTrustStore()
        let clock = ManualClock(start: 1_700_000_000)
        let hostFingerprint = stubFingerprint(0xAA)
        let clientFingerprint = stubFingerprint(0xBB)
        let sharedExporter = Data(repeating: 0xCC, count: 32)
        let hostID = Data(repeating: 0x01, count: 16)

        // First pairing: unknown peer, proves against an open window.
        var window1 = PairingWindow()
        let secret1 = try window1.open(now: Date(timeIntervalSince1970: clock.now()))
        let (host1, client1) = await Self.makeSessionPair(
            clock: clock, hostFingerprint: hostFingerprint, clientFingerprint: clientFingerprint,
            hostID: hostID, peerKnowledge: .unknown, pairingWindow: window1, sharedExporterSecret: sharedExporter
        )
        var hostEvents1 = host1.events.makeAsyncIterator()
        let url1 = try PairingURL(
            version: ProtocolConstants.protocolVersion, hostID: hostID, hostName: "Test Mac",
            addresses: ["127.0.0.1"], tcpPort: 47800, fingerprint: Data(hostFingerprint.bytes), secret: Data(secret1.bytes)
        )
        _ = try await client1.pair(url: url1)
        guard let authenticated1 = await Self.nextEvent(from: &hostEvents1, matching: {
            if case .clientAuthenticated = $0 { return true }
            return false
        }), case .clientAuthenticated(let device1, let viaPairingFlow1) = authenticated1 else {
            Issue.record("expected a clientAuthenticated event from the first pairing")
            return
        }
        #expect(viaPairingFlow1 == true)
        await trustStore.add(TrustedDeviceRecord(
            fingerprint: clientFingerprint, name: device1.name, model: device1.model,
            osVersion: "unknown", firstPaired: Date(), lastSeen: Date()
        ))
        #expect(await trustStore.list().count == 1)
        await client1.close()
        await host1.close()

        // Second pairing: same client identity, now known to the host (the bug's exact
        // reproduction) — a brand new QR/window, exactly as if "Pair new device" were re-shown.
        var window2 = PairingWindow()
        let secret2 = try window2.open(now: Date(timeIntervalSince1970: clock.now()))
        let (host2, client2) = await Self.makeSessionPair(
            clock: clock, hostFingerprint: hostFingerprint, clientFingerprint: clientFingerprint,
            hostID: hostID, peerKnowledge: .known, pairingWindow: window2, sharedExporterSecret: sharedExporter
        )
        var hostEvents2 = host2.events.makeAsyncIterator()
        let url2 = try PairingURL(
            version: ProtocolConstants.protocolVersion, hostID: hostID, hostName: "Test Mac",
            addresses: ["127.0.0.1"], tcpPort: 47800, fingerprint: Data(hostFingerprint.bytes), secret: Data(secret2.bytes)
        )
        let info2 = try await client2.pair(url: url2) // must not hang/throw (this is the reported bug).
        #expect(info2.protocolVersion == ProtocolConstants.protocolVersion)

        guard let authenticated2 = await Self.nextEvent(from: &hostEvents2, matching: {
            if case .clientAuthenticated = $0 { return true }
            return false
        }), case .clientAuthenticated(_, let viaPairingFlow2) = authenticated2 else {
            Issue.record("expected a clientAuthenticated event from the second pairing")
            return
        }
        #expect(viaPairingFlow2 == true) // re-pairing a known peer still runs the full proof flow.
        #expect(await host2.currentState == .authenticated)

        // `SessionManager.recordAuthenticated`'s known-peer branch: update, never a duplicate add.
        if var record = await trustStore.lookup(fingerprint: clientFingerprint) {
            record.lastSeen = Date()
            await trustStore.update(record)
        } else {
            Issue.record("expected the first pairing's record to still be present")
        }
        #expect(await trustStore.list().count == 1)
        }
    }

    /// A known peer's ordinary trusted reconnect (`hello { pairing: false }`) must keep working
    /// unchanged — even now that `SessionManager` always hands `HostSession` a pairing-window
    /// snapshot (needed so a *re-pairing* known peer has one to prove against), a plain reconnect
    /// must never touch it.
    @Test func knownPeerPlainReconnectStillAuthenticatesDirectly() async throws {
        try await withTestTimeout(seconds: 20) {
        let clock = ManualClock(start: 1_700_000_000)
        let hostFingerprint = stubFingerprint(0xAA)
        let clientFingerprint = stubFingerprint(0xBB)
        var window = PairingWindow()
        _ = try window.open(now: Date(timeIntervalSince1970: clock.now())) // open, but unrelated to this reconnect.
        let (host, client) = await Self.makeSessionPair(
            clock: clock, hostFingerprint: hostFingerprint, clientFingerprint: clientFingerprint,
            hostID: Data(repeating: 0x02, count: 16), peerKnowledge: .known, pairingWindow: window,
            sharedExporterSecret: nil
        )
        var hostEventIterator = host.events.makeAsyncIterator()

        let info = try await client.connect()
        #expect(info.protocolVersion == ProtocolConstants.protocolVersion)

        guard let authenticated = await Self.nextEvent(from: &hostEventIterator, matching: {
            if case .clientAuthenticated = $0 { return true }
            return false
        }), case .clientAuthenticated(_, let viaPairingFlow) = authenticated else {
            Issue.record("expected a clientAuthenticated event")
            return
        }
        #expect(viaPairingFlow == false) // a plain trusted reconnect never touches the pairing window.
        #expect(await host.currentState == .authenticated)
        }
    }

    /// Client-side defense (spec decision, see `ClientSession.firstPairingReply`): a host that
    /// answers a pairing `hello` with a bare `helloAck` — never `pairChallenge` — must still
    /// complete `pair(url:)` successfully instead of hanging on a reply that will never come.
    /// Drives a hand-built "fake host" instead of a real `HostSession`, since a real one (after
    /// this fix) always sends this exact reply for the scenario that produces it — this test is
    /// specifically about the client's own robustness to that reply, independent of any one host
    /// implementation.
    @Test func clientAcceptsHelloAckInPlaceOfPairChallenge() async throws {
        try await withTestTimeout(seconds: 20) {
        let clock = ManualClock(start: 1_700_000_000)
        let hostFingerprint = stubFingerprint(0xAA)
        let clientFingerprint = stubFingerprint(0xBB)
        let (clientControl, fakeHostControl) = await InMemoryTransportPair.makeControlPair(
            clientFingerprint: clientFingerprint,
            hostFingerprint: hostFingerprint,
            sharedExporterSecret: nil
        )
        let hostID = Data(repeating: 0x03, count: 16)
        let url = try PairingURL(
            version: ProtocolConstants.protocolVersion, hostID: hostID, hostName: "Test Mac",
            addresses: ["127.0.0.1"], tcpPort: 47800, fingerprint: Data(hostFingerprint.bytes),
            secret: Data(repeating: 0x09, count: 16)
        )
        let client = ClientSession(
            control: clientControl,
            datagramProvider: { _ in InMemoryDatagramChannel() },
            clock: clock,
            localFingerprint: clientFingerprint,
            device: Hello.Device(name: "Test iPhone", model: "iPhone16,1", os: "iOS 18.0", app: "1.0")
        )

        final class EventCapture: @unchecked Sendable {
            var events: [ClientEvent] = []
        }
        let capture = EventCapture()
        let captureTask = Task {
            for await event in client.events { capture.events.append(event) }
        }
        defer { captureTask.cancel() }

        async let pairResult = client.pair(url: url)

        // Drive the fake host side by hand: drain the client's `hello`, then answer with a bare
        // `helloAck` + `sessionKey` — never `pairChallenge` — exactly the spec-decision shortcut a
        // real `HostSession` takes for an already-trusted peer (`HostSessionStateMachine`'s
        // `.tlsAccepted(.known)`/`.helloReceivedPairingTrue` case).
        var iterator = fakeHostControl.incoming.makeAsyncIterator()
        _ = try await iterator.next() // the `hello` frame; its contents don't matter for this test.

        let ack = HelloAck(
            protocol: ProtocolConstants.protocolVersion,
            capabilities: [],
            host: .init(name: "Test Mac", model: "Mac15,6", os: "macOS 15.0", helper: "1.0", id: B64UData(hostID)),
            udpPort: 47800, heartbeatMs: 500, sessionTimeoutMs: 6000, maxTextBytes: 16000, sessionCount: 0
        )
        let ackEnvelope = Envelope(v: ProtocolConstants.protocolVersion, i: 0, message: .helloAck(ack))
        try await fakeHostControl.send(FrameEncoder.encode(kind: .json, body: WireCoding.encodeEnvelope(ackEnvelope)))

        let sessionSecret = try SessionSecret.generate()
        let rawSecret = sessionSecret.key.withUnsafeBytes { Data($0) }
        let keyEnvelope = Envelope(v: ProtocolConstants.protocolVersion, i: 1, message: .sessionKey(
            SessionKeyMessage(sessionID: 42, secret: B64UData(rawSecret), validForMs: 60000)
        ))
        try await fakeHostControl.send(FrameEncoder.encode(kind: .json, body: WireCoding.encodeEnvelope(keyEnvelope)))

        let info = try await pairResult
        #expect(info.protocolVersion == ProtocolConstants.protocolVersion)
        #expect(info.udpPort == 47800)

        await Self.waitUntil {
            capture.events.contains { if case .paired = $0 { return true }; return false }
                && capture.events.contains { if case .connected = $0 { return true }; return false }
        }
        #expect(capture.events.contains { if case .paired = $0 { return true }; return false })
        #expect(capture.events.contains { if case .connected = $0 { return true }; return false })
        }
    }

    /// Regression coverage for the reported "pairs and shows Connected but motion never moves the
    /// cursor" bug: for each of the three ways a client can end up authenticated — first-time
    /// pairing, re-pairing an already-trusted peer, and a plain trusted reconnect — asserts that
    /// `sessionKey` was actually installed (`sendMotion` throwing `CoreError.channelClosed` is
    /// exactly what happens when `sessionID`/`directionalKeys` are still `nil`, or when the UDP
    /// channel `installSessionKey` opens never got assigned — see `ClientSession.sendMotion`'s doc
    /// comment) and that one motion payload sent right after can be sealed and handed to the
    /// datagram channel without throwing.
    @Test func sendMotionSucceedsImmediatelyAfterEachPairingFlow() async throws {
        try await withTestTimeout(seconds: 20) {
        func motionPayload() -> MotionPayload {
            MotionPayload(source: .touch, samples: 1, timestamp: 0, dx: 1, dy: 1, scrollX: 0, scrollY: 0)
        }

        // Flow 1: first-time pairing (unknown peer, full proof round trip).
        let firstPairFixture = try await Self.makeFixture()
        _ = try await firstPairFixture.client.pair(url: firstPairFixture.pairingURL)
        try await firstPairFixture.client.sendMotion(motionPayload())

        // Flow 2: re-pairing a peer the host already trusts (fresh QR/window, known identity).
        let clock2 = ManualClock(start: 1_700_000_000)
        let hostFingerprint2 = stubFingerprint(0xCA)
        let clientFingerprint2 = stubFingerprint(0xCB)
        var repairWindow = PairingWindow()
        let repairSecret = try repairWindow.open(now: Date(timeIntervalSince1970: clock2.now()))
        let hostID2 = Data(repeating: 0x04, count: 16)
        let (repairHost, repairClient) = await Self.makeSessionPair(
            clock: clock2, hostFingerprint: hostFingerprint2, clientFingerprint: clientFingerprint2,
            hostID: hostID2, peerKnowledge: .known, pairingWindow: repairWindow, sharedExporterSecret: nil
        )
        let repairURL = try PairingURL(
            version: ProtocolConstants.protocolVersion, hostID: hostID2, hostName: "Test Mac",
            addresses: ["127.0.0.1"], tcpPort: 47800, fingerprint: Data(hostFingerprint2.bytes),
            secret: Data(repairSecret.bytes)
        )
        _ = try await repairClient.pair(url: repairURL)
        try await repairClient.sendMotion(motionPayload())
        await repairHost.close()

        // Flow 3: plain trusted reconnect (`hello { pairing: false }`).
        let clock3 = ManualClock(start: 1_700_000_000)
        let hostFingerprint3 = stubFingerprint(0xDA)
        let clientFingerprint3 = stubFingerprint(0xDB)
        let (reconnectHost, reconnectClient) = await Self.makeSessionPair(
            clock: clock3, hostFingerprint: hostFingerprint3, clientFingerprint: clientFingerprint3,
            hostID: Data(repeating: 0x05, count: 16), peerKnowledge: .known, pairingWindow: nil,
            sharedExporterSecret: nil
        )
        _ = try await reconnectClient.connect()
        try await reconnectClient.sendMotion(motionPayload())
        await reconnectHost.close()
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

    /// Regression coverage for the bug where a UDP channel that cannot send at all — closed,
    /// torn down, or (per `NWDatagramChannel`'s real-device report) never reaching `.ready` — left
    /// `ProbeController` fed *no* outcomes whatsoever (`sendProbe()` used to just `return` early on
    /// a nil/failing channel, without recording a loss), so it could never reach the "8 straight
    /// unanswered" or "≥11 of 12 unanswered" thresholds that engage TCP fallback (spec §3.5.8) —
    /// motion stayed silently stuck retrying a UDP path that would never come back, forever.
    /// `InMemoryDatagramChannel.send` throws `CoreError.channelClosed` once `close()`'d, which is
    /// exactly the "channel throws" half of that fix (`ClientSession.sendProbe`'s new `do`/`catch`
    /// around `channel.send`).
    @Test func closedDatagramChannelThrowingOnSendStillTriggersFallback() async throws {
        try await withTestTimeout(seconds: 20) {
        let fixture = try await Self.makeFixture()
        var hostEventIterator = fixture.host.events.makeAsyncIterator()
        _ = try await fixture.client.pair(url: fixture.pairingURL)
        _ = await Self.nextEvent(from: &hostEventIterator) {
            if case .clientAuthenticated = $0 { return true }
            return false
        }

        // The channel itself now throws on every `send` — not a dropped-in-flight packet, but the
        // transport being unusable outright.
        fixture.clientDatagram.close()

        for _ in 0..<7 {
            try await fixture.client.sendProbe() // must not throw out of `sendProbe()` itself.
            #expect(!(await fixture.client.currentStats().isFallbackEngaged))
        }
        try await fixture.client.sendProbe() // 8th straight failure -> fallback (spec's ~2 s window).
        #expect(await fixture.client.currentStats().isFallbackEngaged)

        // Motion now rides the TCP fallback path instead of silently failing forever.
        for index in 0..<3 {
            let payload = MotionPayload(source: .touch, samples: 1, timestamp: UInt32(index), dx: 1, dy: 1, scrollX: 0, scrollY: 0)
            try await fixture.client.sendMotion(payload)
        }
        try await fixture.client.flushPendingMotionBatch()

        var tcpMotionCount = 0
        while tcpMotionCount < 3 {
            guard let event = await hostEventIterator.next() else { break }
            if case .motion(let motion) = event, motion.channel == .tcp {
                tcpMotionCount += 1
            }
        }
        #expect(tcpMotionCount == 3)
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
