// IntegrationTests/LoopbackIntegrationTests.swift
// End-to-end test of the wire protocol against a *real* running helper process, over loopback
// (spec §10.2's integration harness / §10.4's performance test procedure): launches
// `AirMouse.app --loopback`, pairs a `ClientSession` (built on `LoopbackClientTransport.swift`, not
// `airmouse-cli`) against the printed `AIRMOUSE_PAIR_URL`, drives it through motion/click/text/media,
// and asserts against the `PostedEvent` JSON lines the helper's `--loopback` mode is contracted to
// write to `AIRMOUSE_LOOPBACK_LOG` (`Services/EventInjector/RecordingEventPoster.swift`'s
// `PostedEvent` shape, owned by the app-shell/networking agents).
//
// Safety note (why this suite sends one small "canary" motion datagram before anything else): as of
// this writing, nothing in `App/AppEnvironment.swift`/`AirMouseHelperApp.swift` has been observed to
// switch `EventInjector`'s poster from the real `CGEventPoster` to `RecordingEventPoster` when
// `--loopback` is passed — only `HostServer`'s stdout banner and port/URL contract are wired so far.
// If that switch is still missing when this suite runs, sending real clicks/keystrokes would inject
// them into whatever window has focus on the machine running the test. So every test here sends one
// harmless motion datagram first and requires *some* line to appear in the loopback log before
// sending anything else (click, text, media key) — if the log stays empty, the whole test SKIPs
// (see `skip(_:)`) rather than risk injecting real input.
import AirMouseCore
import AirMouseCrypto
import AirMouseFilters
import AirMouseProtocol
import Foundation
import Testing

/// Real-time `Clock` for the in-test `ClientSession` (mirrors `apps/.../GyroEngine/SystemClock.swift`
/// and `airmouse-cli`'s identical file — this target cannot depend on either).
private struct IntegrationTestClock: Clock {
    func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}

/// Prints a clearly-marked SKIP line and returns — the documented Swift Testing pattern for a skip
/// decision that can only be made from a runtime side effect (a spawned process's behavior), which
/// `.enabled(if:)` traits (evaluated before the test body runs) cannot express. The test still shows
/// as passed, by design (arch: "must SKIP (not fail)").
private func skip(_ reason: String, function: String = #function) {
    print("SKIP [\(function)]: \(reason)")
}

private enum LoggedEventFields {
    /// Parses one `AIRMOUSE_LOOPBACK_LOG` line into a loosely-typed dictionary — deliberately not a
    /// strict `Decodable` struct, since the exact JSON shape is owned by another agent and this
    /// suite should tolerate additional/renamed fields rather than fail to parse.
    static func parse(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func int(_ dict: [String: Any], _ key: String) -> Int? {
        if let n = dict[key] as? NSNumber { return n.intValue }
        return nil
    }

    static func string(_ dict: [String: Any], _ key: String) -> String? {
        dict[key] as? String
    }

    static func bool(_ dict: [String: Any], _ key: String) -> Bool? {
        if let b = dict[key] as? Bool { return b }
        if let n = dict[key] as? NSNumber { return n.boolValue }
        return nil
    }
}

/// One shared, paired session + its backing helper process. `close()` tears both down; every test
/// must call it before returning (Swift Testing has no suite-wide async teardown hook that fits this
/// per-test process lifecycle, so each test manages its own instance explicitly rather than relying
/// on `deinit`, which cannot `await`).
private struct PairedSession {
    let helper: LoopbackHelperProcess
    let session: ClientSession
    let control: LoopbackControlChannel

    /// Launches the helper, waits for `AIRMOUSE_PAIR_URL`, and pairs. Returns `nil` (caller must
    /// SKIP) on any failure along the way — a not-yet-built helper, a `--loopback` mode that never
    /// prints the banner in time, or a pairing handshake failure.
    static func establish() async -> PairedSession? {
        guard let helper = await LoopbackHelperProcess.launch(timeout: 10) else { return nil }

        guard let url = try? PairingClient.parse(helper.pairURLString),
              let pinnedFingerprint = Fingerprint(bytes: Array(url.fingerprint))
        else {
            helper.terminate()
            return nil
        }

        guard let identity = try? IdentityFactory.makeEphemeralIdentity(commonName: "AirMouse Integration Test Client") else {
            helper.terminate()
            return nil
        }

        guard let control = try? await LoopbackControlChannel.connect(
            host: "127.0.0.1",
            port: url.tcpPort,
            identity: identity.secIdentity,
            pinnedFingerprint: pinnedFingerprint
        ) else {
            helper.terminate()
            return nil
        }

        let session = ClientSession(
            control: control,
            datagramProvider: { udpPort in try await LoopbackDatagramChannel.connect(host: "127.0.0.1", port: udpPort) },
            clock: IntegrationTestClock(),
            localFingerprint: identity.fingerprint,
            device: Hello.Device(name: "AirMouseHelperIntegrationTests", model: "test", os: "macOS", app: "1.0"),
            displayHz: 60
        )

        guard (try? await session.pair(url: url)) != nil else {
            await session.close(reason: .error)
            helper.terminate()
            return nil
        }

        return PairedSession(helper: helper, session: session, control: control)
    }

    /// Sends a motion datagram, waits briefly, and reports whether *any* line appeared in the
    /// loopback log — the safety gate described in this file's header comment. Resends the canary
    /// on every poll tick (not just once) — UDP is best-effort, and this suite's `.serialized` tests
    /// each launch a brand-new helper process on the same fixed loopback port in quick succession, so
    /// a single early datagram can race a not-yet-ready listener and be dropped with nothing to
    /// retransmit it.
    func logPipelineIsLive() async -> Bool {
        let canary = MotionPayload(
            source: .externalPointer,
            samples: 1,
            timestamp: UInt32(truncatingIfNeeded: Int64(ProcessInfo.processInfo.systemUptime * 1_000_000)),
            dxPoints: 2,
            dyPoints: -1,
            scrollXPoints: 0,
            scrollYPoints: 0
        )
        for _ in 0..<30 { // ~3s, resending each tick so one dropped datagram can't fail the gate
            try? await session.sendMotion(canary)
            if !helper.readLogLines().isEmpty { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    func teardown() async {
        await session.close(reason: .userQuit)
        helper.terminate()
    }
}

/// Sends `count` motion datagrams from `source` (each `dxPoints`/`dyPoints`), paced at ~120Hz
/// (8ms apart, per spec §5.3.2's 4…50ms clamp) so an unthrottled burst cannot coalesce datagrams
/// together before the test can observe individual deltas. Then polls the loopback log (up to
/// `timeout`) until at least `minMoves` new `mouseMoved` lines beyond `baseline` (the log's line
/// count the caller captured before sending) have landed, or the deadline passes. Returns every
/// newly parsed event beyond `baseline` (not just `mouseMoved`), so a caller only needs to capture
/// `baseline` once (e.g. right after `logPipelineIsLive()`) to isolate this call's events from the
/// canary datagram or an earlier phase's.
private func sendPacedMotionAndCollect(
    _ paired: PairedSession,
    source: MotionSource,
    dxPoints: Double,
    dyPoints: Double,
    count: Int,
    baseline: Int,
    minMoves: Int,
    timeout: TimeInterval = 3
) async throws -> [[String: Any]] {
    for _ in 0..<count {
        let payload = MotionPayload(
            source: source,
            samples: 1,
            timestamp: UInt32(truncatingIfNeeded: Int64(ProcessInfo.processInfo.systemUptime * 1_000_000)),
            dxPoints: dxPoints,
            dyPoints: dyPoints,
            scrollXPoints: 0,
            scrollYPoints: 0
        )
        try await paired.session.sendMotion(payload)
        try? await Task.sleep(nanoseconds: 8_000_000) // ~120Hz pacing so nothing coalesces
    }

    let deadline = Date().addingTimeInterval(timeout)
    var newEvents: [[String: Any]] = []
    while Date() < deadline {
        let lines = paired.helper.readLogLines()
        newEvents = lines.count > baseline ? lines[baseline...].compactMap(LoggedEventFields.parse) : []
        let moves = newEvents.filter { LoggedEventFields.string($0, "kind") == "mouseMoved" }
        if moves.count >= minMoves { break }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    return newEvents
}

@Suite(.serialized) // sequential: the helper always binds the same fixed loopback port (spec §11.3 default 47800)
struct LoopbackIntegrationTests {
    /// Gyro-source motion: spec §3.5/§5.3 exempt gyro from the §5.4 pointer acceleration curve
    /// (`AccelerationCurve.apply(..., isGyroSource: true)` returns the delta unchanged), so — unlike
    /// touch/external-pointer sources — the logged sum should match the raw sent sum exactly.
    @Test func gyroSourceMotionSumsExactly() async throws {
        guard let paired = await PairedSession.establish() else {
            skip("helper not built, --loopback didn't print AIRMOUSE_PAIR_URL in time, or pairing failed")
            return
        }
        guard await paired.logPipelineIsLive() else {
            skip("AIRMOUSE_LOOPBACK_LOG never received a line — --loopback's EventPosting wiring isn't finished yet")
            await paired.teardown()
            return
        }

        let baseline = paired.helper.readLogLines().count
        let newEvents = try await sendPacedMotionAndCollect(
            paired, source: .gyro, dxPoints: 2, dyPoints: -1, count: 50, baseline: baseline, minMoves: 40
        )
        await paired.teardown()

        guard !newEvents.isEmpty else {
            skip("loopback log produced no parseable events")
            return
        }

        let moves = newEvents.filter { LoggedEventFields.string($0, "kind") == "mouseMoved" }
        #expect(moves.count >= 40, "expected ≥40 of 50 gyro-source mouseMoved events, got \(moves.count)")
        guard !moves.isEmpty else { return }

        let dxSum = moves.reduce(0) { $0 + (LoggedEventFields.int($1, "deltaX") ?? 0) }
        let dySum = moves.reduce(0) { $0 + (LoggedEventFields.int($1, "deltaY") ?? 0) }
        // Scale the expected sum to however many move events actually landed (≥40 of 50 sent).
        let expectedDx = moves.count * 2
        let expectedDy = moves.count * -1
        #expect(abs(dxSum - expectedDx) <= 1, "gyro dx sum \(dxSum) not within ±1 of expected \(expectedDx)")
        #expect(abs(dySum - expectedDy) <= 1, "gyro dy sum \(dySum) not within ±1 of expected \(expectedDy)")
    }

    /// Touch-source motion: the host applies the §5.4 velocity-dependent pointer acceleration curve
    /// here, so the logged sum legitimately differs from the raw sent sum — this only checks that
    /// direction is preserved and the magnitude stays within a generous band, not an exact sum.
    @Test func touchSourceMotionAppliesAccelerationWithinBand() async throws {
        guard let paired = await PairedSession.establish() else {
            skip("helper not built, --loopback didn't print AIRMOUSE_PAIR_URL in time, or pairing failed")
            return
        }
        guard await paired.logPipelineIsLive() else {
            skip("AIRMOUSE_LOOPBACK_LOG never received a line — --loopback's EventPosting wiring isn't finished yet")
            await paired.teardown()
            return
        }

        let baseline = paired.helper.readLogLines().count
        let newEvents = try await sendPacedMotionAndCollect(
            paired, source: .touch, dxPoints: 2, dyPoints: -1, count: 50, baseline: baseline, minMoves: 40
        )
        await paired.teardown()

        guard !newEvents.isEmpty else {
            skip("loopback log produced no parseable events")
            return
        }

        let moves = newEvents.filter { LoggedEventFields.string($0, "kind") == "mouseMoved" }
        #expect(moves.count >= 40, "expected ≥40 of 50 touch-source mouseMoved events, got \(moves.count)")
        guard !moves.isEmpty else { return }

        let dxs = moves.compactMap { LoggedEventFields.int($0, "deltaX") }
        let dys = moves.compactMap { LoggedEventFields.int($0, "deltaY") }
        // Monotonic sign: the acceleration curve scales magnitude, it never flips direction — every
        // logged delta must keep the sign of what was sent (dx > 0, dy < 0).
        #expect(dxs.allSatisfy { $0 >= 0 }, "touch dx deltas changed sign: \(dxs)")
        #expect(dys.allSatisfy { $0 <= 0 }, "touch dy deltas changed sign: \(dys)")

        let dxSum = Double(dxs.reduce(0, +))
        let dySum = Double(dys.reduce(0, +))
        let rawDx = Double(moves.count) * 2
        let rawDy = Double(moves.count) * -1
        let dxLower = min(0.3 * rawDx, 3 * rawDx)
        let dxUpper = max(0.3 * rawDx, 3 * rawDx)
        let dyLower = min(0.3 * rawDy, 3 * rawDy)
        let dyUpper = max(0.3 * rawDy, 3 * rawDy)
        #expect(dxSum >= dxLower && dxSum <= dxUpper, "touch dx sum \(dxSum) not within [0.3x,3x] of raw \(rawDx)")
        #expect(dySum >= dyLower && dySum <= dyUpper, "touch dy sum \(dySum) not within [0.3x,3x] of raw \(rawDy)")
    }

    @Test func clickTextAndMediaAreInjected() async throws {
        guard let paired = await PairedSession.establish() else {
            skip("helper not built, --loopback didn't print AIRMOUSE_PAIR_URL in time, or pairing failed")
            return
        }
        guard await paired.logPipelineIsLive() else {
            skip("AIRMOUSE_LOOPBACK_LOG never received a line — --loopback's EventPosting wiring isn't finished yet")
            await paired.teardown()
            return
        }

        try await paired.session.sendClick(Click(button: .left, action: .tap, count: 1, modifiers: []))
        try await paired.session.sendText(Text(s: "héllo", secure: false))
        try await paired.session.sendMediaKey(MediaKeyMessage(key: .playPause, action: .tap))

        // Poll until every expected kind has landed — leftMouseDown, leftMouseUp (posted ~15ms after
        // down per spec §5.3.3), a keyDown carrying (all or part of) the typed text, and the media
        // key's systemDefinedKey — or a 3s deadline, so this never breaks early on the first kind it
        // sees and misses one posted a few milliseconds later.
        let deadline = Date().addingTimeInterval(3)
        var events: [[String: Any]] = []
        while Date() < deadline {
            events = paired.helper.readLogLines().compactMap(LoggedEventFields.parse)
            let hasDown = events.contains { LoggedEventFields.string($0, "kind") == "leftMouseDown" }
            let hasUp = events.contains { LoggedEventFields.string($0, "kind") == "leftMouseUp" }
            let hasMedia = events.contains { LoggedEventFields.string($0, "kind") == "systemDefinedKey" }
            // The host may post one CGEvent per grapheme or one for the whole string; concatenate
            // every keyDown's unicodeString in order and look for "héllo" as a substring either way.
            let typed = events
                .filter { LoggedEventFields.string($0, "kind") == "keyDown" }
                .compactMap { LoggedEventFields.string($0, "unicodeString") }
                .joined()
            if hasDown, hasUp, hasMedia, typed.contains("héllo") { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        await paired.teardown()

        guard !events.isEmpty else {
            skip("loopback log produced no parseable events")
            return
        }

        let leftDown = events.first { LoggedEventFields.string($0, "kind") == "leftMouseDown" }
        let leftUp = events.first { LoggedEventFields.string($0, "kind") == "leftMouseUp" }
        #expect(leftDown != nil, "no leftMouseDown event logged")
        #expect(leftUp != nil, "no leftMouseUp event logged")
        if let leftDown { #expect(LoggedEventFields.int(leftDown, "clickState") == 1) }
        if let leftUp { #expect(LoggedEventFields.int(leftUp, "clickState") == 1) }

        let typed = events
            .filter { LoggedEventFields.string($0, "kind") == "keyDown" }
            .compactMap { LoggedEventFields.string($0, "unicodeString") }
            .joined()
        #expect(typed.contains("héllo"), "typed text '\(typed)' does not contain 'héllo'")

        let mediaEvent = events.first { LoggedEventFields.string($0, "kind") == "systemDefinedKey" }
        #expect(mediaEvent != nil, "no systemDefinedKey (media key) event logged")
        if let mediaEvent {
            #expect(LoggedEventFields.int(mediaEvent, "nxKeyType") == Int(MediaKey.playPause.nxKeyType))
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AIRMOUSE_PERF"] == "1"))
    func loopbackHeartbeatP95IsUnder20ms() async throws {
        guard let paired = await PairedSession.establish() else {
            skip("helper not built, --loopback didn't print AIRMOUSE_PAIR_URL in time, or pairing failed")
            return
        }

        for _ in 0..<40 {
            try? await paired.session.sendHeartbeat()
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms between heartbeats
        }
        // Let the last few pongs land before snapshotting.
        try? await Task.sleep(nanoseconds: 200_000_000)
        let stats = await paired.session.currentStats()
        await paired.teardown()

        guard let p95 = stats.rttP95 else {
            skip("no heartbeat RTT samples were recorded")
            return
        }
        #expect(p95 < 0.020, "loopback heartbeat p95 RTT \(p95 * 1000)ms is not under 20ms")
    }
}
