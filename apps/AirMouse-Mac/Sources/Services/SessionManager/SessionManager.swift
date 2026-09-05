// SessionManager — spec §3.3 (reconnect), §3.4 (control channel messages), §3.4.6 (heartbeat/
// timeouts), §5.3 (event injection), §5.5 (macros), §5.6 (revocation); arch §3.3's `SessionManager`
// row. Owned by the networking agent (assignment: "Services/SessionManager/").
//
// Per accepted connection, builds one `AirMouseCore.HostSession`, consumes its `events` stream and
// drives the shared `EventInjector`, forwards `macroInvoke` to `MacroEngine`, and pushes `hostState`/
// `macroList` updates. A single 1 s ticker (spec §3.4.6's heartbeat/stale/close timeouts) also
// detects a session's `sessionID` becoming available (so the matching `NWDatagramChannel` can be
// attached) — `AirMouseCore.HostSession` has no dedicated event for that. An unauthenticated
// (pairing) session completing authentication *does* have one (`.clientAuthenticated(device:)`), so
// adding the new device to `TrustStore` is handled synchronously from that event instead (`handle
// (event:sessionKey:)`'s `.clientAuthenticated` case) rather than polled here — see that case's
// comment for why polling lost the race against a fast pair-then-disconnect.
import AirMouseCore
import AirMouseCrypto
import AirMouseFilters
import AirMouseProtocol
import Foundation
import os

/// `HostSession`'s `clock: any Clock` needs to be usable as `Date(timeIntervalSince1970:
/// clock.now())` (that's exactly how `HostSession` checks `PairingWindow.isOpen`/records proof
/// attempts) — so, unlike `EventInjector`'s `SystemUptimeClock` (`ProcessInfo.systemUptime`, a
/// process-relative origin), every `HostSession` in this file is given a *wall-clock* `Clock`
/// whose origin is the Unix epoch, matching `PairingSecret.issuedAt = Date()` from
/// `PairingService.openWindow()`.
public struct HostWallClock: Clock {
    public init() {}
    public func now() -> TimeInterval { Date().timeIntervalSince1970 }
}

public actor SessionManager {
    private struct Managed {
        let session: HostSession
        let localID: String
        /// Wraps the raw channel `HostSession` was constructed with; its `lastActivity()` stands in
        /// for "a heartbeat last arrived" (see `ActivityTrackingControlChannel`'s doc comment).
        let activityChannel: ActivityTrackingControlChannel
        var fingerprint: Fingerprint?
        var wasUnknownAtAccept: Bool
        var deviceName: String
        var deviceModel: String
        var udpAttached = false
        var pairingRecorded = false
        var lastMotionTimestampBySource: [MotionSource: UInt32] = [:]
        var eventTask: Task<Void, Never>?
    }

    private let eventInjector: EventInjector
    private let macroEngine: MacroEngine
    private let macroStore: any MacroStoreProviding
    private let trustStore: TrustStore
    private let pairingService: PairingService
    private let udpHub: NWUDPHub
    private let hostStateSnapshotProvider: @Sendable () async -> HostStateSnapshot
    private let globalScriptsEnabledProvider: @Sendable () async -> Bool
    private let clock: any Clock = HostWallClock()
    private let helperVersion: String
    private let osVersionString: String

    /// Set only in `--loopback` mode (spec §8 launch arguments); drains newly-posted
    /// `RecordingEventPoster` events to `loopbackLogURL` as JSON lines (contract with the
    /// airmouse-cli/integration-test agent).
    private let recordingPoster: RecordingEventPoster?
    private let loopbackLogURL: URL?
    private var loopbackLogHandle: FileHandle?
    private var loopbackRecordedCount = 0

    private var sessions: [String: Managed] = [:]
    private var lastHostState: HostStateSnapshot?
    private var tickerTask: Task<Void, Never>?
    private var macroChangesTask: Task<Void, Never>?

    public init(
        eventInjector: EventInjector,
        macroEngine: MacroEngine,
        macroStore: any MacroStoreProviding,
        trustStore: TrustStore,
        pairingService: PairingService,
        udpHub: NWUDPHub,
        hostStateSnapshotProvider: @escaping @Sendable () async -> HostStateSnapshot,
        globalScriptsEnabledProvider: @escaping @Sendable () async -> Bool,
        helperVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
        recordingPoster: RecordingEventPoster? = nil,
        loopbackLogURL: URL? = nil
    ) {
        self.eventInjector = eventInjector
        self.macroEngine = macroEngine
        self.macroStore = macroStore
        self.trustStore = trustStore
        self.pairingService = pairingService
        self.udpHub = udpHub
        self.hostStateSnapshotProvider = hostStateSnapshotProvider
        self.globalScriptsEnabledProvider = globalScriptsEnabledProvider
        self.helperVersion = helperVersion
        self.osVersionString = "macOS " + ProcessInfo.processInfo.operatingSystemVersionString
        self.recordingPoster = recordingPoster
        self.loopbackLogURL = loopbackLogURL
        Task { await self.startBackgroundWork() }
    }

    private func startBackgroundWork() {
        guard tickerTask == nil else { return }
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self?.tick()
            }
        }
        macroChangesTask = Task { [weak self] in
            guard let self else { return }
            for await list in await self.macroStore.changes() {
                await self.broadcastMacroList(list)
            }
        }
        if let loopbackLogURL {
            FileManager.default.createFile(atPath: loopbackLogURL.path, contents: nil)
            loopbackLogHandle = try? FileHandle(forWritingTo: loopbackLogURL)
        }
    }

    // MARK: - HostServer-facing surface

    public var connectedSessions: [ConnectedSessionInfo] {
        get async {
            var infos: [ConnectedSessionInfo] = []
            for managed in sessions.values {
                let state = await managed.session.currentState
                guard state == .authenticated || state == .stale else { continue }
                infos.append(ConnectedSessionInfo(
                    id: managed.localID,
                    deviceName: managed.deviceName,
                    model: managed.deviceModel,
                    latencyMillis: nil
                ))
            }
            return infos
        }
    }

    public var pendingSessionCount: Int {
        get async {
            var count = 0
            for managed in sessions.values {
                let state = await managed.session.currentState
                if case .tlsAccepted = state { count += 1 }
                if case .pairing = state { count += 1 }
            }
            return count
        }
    }

    public var totalSessionCount: Int { sessions.count }

    public func disconnect(sessionID: String) async {
        guard let managed = sessions[sessionID] else { return }
        await managed.session.close(reason: .hostQuit)
    }

    public func closeAll(reason: GoodbyeReason) async {
        for managed in sessions.values {
            await managed.session.close(reason: reason)
        }
    }

    /// `TrustStore.onRevoked` wires into this (spec §5.6: "close the session within 1 s").
    public func closeSession(fingerprint: Fingerprint, reason: GoodbyeReason) async {
        for managed in sessions.values where managed.fingerprint == fingerprint {
            await managed.session.close(reason: reason)
        }
    }

    // MARK: - Accepting a new connection (called by `HostServer`)

    public func acceptConnection(
        channel: any ControlChannel,
        trustedFingerprints: Set<Fingerprint>,
        pairingWindow: CorePairingWindow?,
        hostIdentity: GeneratedIdentity,
        hostID: Data,
        hostName: String,
        udpPort: Int
    ) async {
        let peerFingerprint = await channel.peerFingerprint
        let knowledge: HostPeerKnowledge = (peerFingerprint.map { trustedFingerprints.contains($0) } ?? false) ? .known : .unknown

        let identity = HostSession.HostIdentity(
            hostID: hostID,
            name: hostName,
            model: HostServerSettings.currentMachineModel(),
            os: osVersionString,
            helperVersion: helperVersion,
            fingerprint: hostIdentity.fingerprint
        )
        let snapshot = await hostStateSnapshotProvider()
        let hostState = Self.hostState(from: snapshot, sessionCount: sessions.count, globalScriptsEnabled: await globalScriptsEnabledProvider())
        let macros = await macroStore.list()
        let revision = await macroStore.revision

        // see `ActivityTrackingControlChannel`'s doc comment: `HostSession` never surfaces a
        // heartbeat's arrival through `events`, so this decorator is the only way to keep
        // `checkTimeouts(now:lastHeartbeatAt:)` fed with a real, advancing timestamp.
        let activityChannel = ActivityTrackingControlChannel(wrapping: channel, clock: clock)
        let session = HostSession(
            control: activityChannel,
            clock: clock,
            identity: identity,
            peerKnowledge: knowledge,
            pairingWindow: knowledge == .unknown ? pairingWindow : nil,
            hostState: hostState,
            macros: macros,
            macroRevision: revision,
            udpPort: udpPort
        )

        let localID = UUID().uuidString
        var managed = Managed(
            session: session,
            localID: localID,
            activityChannel: activityChannel,
            fingerprint: peerFingerprint,
            wasUnknownAtAccept: knowledge == .unknown,
            deviceName: "New device",
            deviceModel: "unknown"
        )
        sessions[localID] = managed
        if knowledge == .unknown {
            await pairingService.noteDeviceConnecting()
        }

        await session.start()
        let task = Task { [weak self] in
            guard let self else { return }
            for await event in session.events {
                await self.handle(event: event, sessionKey: localID)
            }
            await self.sessionEnded(sessionKey: localID)
        }
        managed.eventTask = task
        sessions[localID] = managed
    }

    private func sessionEnded(sessionKey: String) async {
        sessions.removeValue(forKey: sessionKey)
        await eventInjector.releaseAll()
    }

    // MARK: - 1 s ticker (spec §3.4.6 + this file's header note)

    private func tick() async {
        let now = clock.now()
        // spec §3.1.4: "when it reaches 0 while the window is visible a new secret and QR are
        // generated automatically." `PairingWindowView` also drives this from the UI, but this
        // ticker is the only thing keeping the window alive in `--loopback` mode (no UI at all) —
        // harmless, idempotent redundancy the rest of the time (`regenerateIfExpired` is a no-op
        // unless the current secret has actually expired).
        try? await pairingService.regenerateIfExpired()
        for key in Array(sessions.keys) {
            guard var managed = sessions[key] else { continue }

            if !managed.udpAttached, let sessionID = await managed.session.currentSessionID {
                let channel = udpHub.register(sessionID: sessionID)
                await managed.session.attachDatagramChannel(channel)
                managed.udpAttached = true
                sessions[key] = managed
            }

            // Trust recording for a newly-authenticated pairing session used to happen here (polled,
            // once a second) — see this file's header note, and the report for why that's exactly
            // the race that made a fast pair-then-disconnect (e.g. `airmouse-cli pair`, which closes
            // the control connection the instant `ClientSession.pair(url:)` returns) lose the trust
            // record entirely: `HostSession.teardown()` doesn't touch `state`, but it does finish the
            // `events` stream right after yielding `.clientDisconnected`, which ends this session's
            // `sessions[key]` entry (`sessionEnded`, driven by that same stream) well inside the ~1s
            // this ticker could still be sleeping. `HostSession` already emits a dedicated
            // `.clientAuthenticated(device:)` event exactly when `state` reaches `.authenticated`
            // (both for this pairing-completion path and a trusted reconnect's `hello`) — `handle
            // (event:sessionKey:)`'s `.clientAuthenticated` case (`recordAuthenticated` below) now
            // does the trust-store write synchronously, in the same event-stream task that will go
            // on to observe `.clientDisconnected`/end-of-stream, so it always runs first. No polling
            // needed for this.

            await managed.session.checkTimeouts(now: now, lastHeartbeatAt: managed.activityChannel.lastActivity())
        }
        await drainLoopbackLog()
    }

    // MARK: - HostEvent → EventInjector / MacroEngine (spec §5.3, §5.5)

    private func handle(event: HostEvent, sessionKey: String) async {
        switch event {
        case .motion(let delta):
            await applyMotion(delta, sessionKey: sessionKey)
        case .click(let click):
            await applyClick(click)
        case .scrollPhase(let phase):
            await applyScrollPhase(phase)
        case .modifiers(let modifiers):
            await eventInjector.setModifiers(modifiers.flags)
        case .key(let key):
            await applyKey(key)
        case .text(let text):
            await eventInjector.typeText(text.s)
        case .deleteBackward(let deleteBackward):
            await eventInjector.deleteBackward(count: deleteBackward.count, forward: deleteBackward.forward)
        case .mediaKey(let mediaKey):
            await applyMediaKey(mediaKey)
        case .volume:
            break // spec §5.3.7: volume/CoreAudio is out of EventInjector's scope (see that module's header).
        case .macroInvoke(let invoke, let messageID):
            await handleMacroInvoke(invoke, messageID: messageID, sessionKey: sessionKey)
        case .recenter:
            await eventInjector.recenter()
        case .settings:
            break // per-session settings layering is a Preferences/session-settings concern, not injection.
        case .clientAuthenticated(let device):
            await recordAuthenticated(sessionKey: sessionKey, device: device)
            await attachDatagramChannelIfNeeded(sessionKey: sessionKey)
        case .clientDisconnected:
            break
        case .releaseHeldInputs:
            await eventInjector.releaseAll()
        }
        await drainLoopbackLog()
    }

    /// Fires exactly once per session, the instant `HostSession`'s state machine reaches
    /// `.authenticated` (spec §3.2.1(a)/(b)) — for both a trusted reconnect's `hello` and a
    /// just-completed pairing flow. For the pairing case (`wasUnknownAtAccept`), this is also where
    /// the new device is written to `TrustStore`: doing it here, synchronously in this event-stream
    /// task, guarantees it happens before this same task can observe end-of-stream and call
    /// `sessionEnded` (`HostSession.teardown()` yields `.clientDisconnected` and finishes the stream,
    /// but never touches `state`) — so a client that pairs and disconnects immediately (e.g.
    /// `airmouse-cli pair`) can never race a slower, once-a-second-polled write and lose the record.
    private func recordAuthenticated(sessionKey: String, device: Hello.Device) async {
        guard var managed = sessions[sessionKey] else { return }
        managed.deviceName = device.name
        managed.deviceModel = device.model
        sessions[sessionKey] = managed
        guard let fingerprint = managed.fingerprint else { return }

        guard managed.wasUnknownAtAccept, !managed.pairingRecorded else {
            Task { await trustStore.updateLastSeen(fingerprint: fingerprint, date: Date()) }
            return
        }

        let record = CoreTrustedDeviceRecord(
            fingerprint: fingerprint,
            name: managed.deviceName,
            model: managed.deviceModel,
            osVersion: "unknown",
            firstPaired: Date(),
            lastSeen: Date(),
            allowScripts: false,
            revoked: false
        )
        let added = await trustStore.add(record)
        if added {
            await pairingService.markConsumedByPairingSuccess(deviceName: managed.deviceName)
        } else {
            // spec §3.2.6 "20 trusted devices already" — the host verify block already let this
            // handshake through (a race against the cap), so just close it.
            try? await managed.session.sendError(ErrorPayload(code: .pairingTooManyDevices, message: "too many trusted devices", fatal: true))
        }
        managed.pairingRecorded = true
        sessions[sessionKey] = managed
    }

    /// Best-effort, low-latency counterpart to the 1s ticker's own `udpAttached` check (`tick()`):
    /// a client only sends its first motion datagram after receiving the `sessionKey` message
    /// (`HostSession.issueSessionKey()`, called synchronously right after this very event is
    /// yielded — spec's `helloAck`-then-`sessionKey` order), so `currentSessionID` is *typically*
    /// already set by the time this runs; a short bounded retry (not a single check) absorbs the
    /// remaining scheduling race between `HostSession`'s actor finishing `issueSessionKey()` and
    /// this event actually being handled here. Without this, a client that sends motion immediately
    /// after pairing/reconnecting (e.g. the integration-test suite's canary datagram, or a real
    /// client moving the mouse right away) could have its first datagrams arrive at `udpHub` before
    /// `tick()` next runs (up to ~1s later) and get silently dropped — nothing buffers them for an
    /// unregistered `sessionID`. `tick()`'s check stays as the ultimate fallback if this still races.
    private func attachDatagramChannelIfNeeded(sessionKey: String) async {
        for _ in 0..<20 { // ~200ms at 10ms steps.
            guard var managed = sessions[sessionKey], !managed.udpAttached else { return }
            guard let sessionID = await managed.session.currentSessionID else {
                try? await Task.sleep(nanoseconds: 10_000_000)
                continue
            }
            let channel = udpHub.register(sessionID: sessionID)
            await managed.session.attachDatagramChannel(channel)
            managed.udpAttached = true
            sessions[sessionKey] = managed
            return
        }
    }

    private func applyMotion(_ delta: MotionDeltaEvent, sessionKey: String) async {
        guard delta.shouldApply else { return } // spec §3.5.4: stale-apply window.
        let payload = delta.payload
        var interval: TimeInterval = 0.008
        if var managed = sessions[sessionKey] {
            if let previous = managed.lastMotionTimestampBySource[payload.source] {
                let deltaUs = payload.timestamp &- previous // wraps every ~71.6 min (spec §3.5.2).
                interval = min(0.050, max(0.004, Double(deltaUs) / 1_000_000))
            }
            managed.lastMotionTimestampBySource[payload.source] = payload.timestamp
            sessions[sessionKey] = managed
        }
        if payload.dx != 0 || payload.dy != 0 || payload.flags.contains(.motionEnd) {
            await eventInjector.applyMotion(
                dx: payload.dxPoints,
                dy: payload.dyPoints,
                source: payload.source,
                flags: payload.flags,
                sampleInterval: interval
            )
        }
        if payload.scrollX != 0 || payload.scrollY != 0 {
            await eventInjector.scroll(phase: .changed, dx: payload.scrollXPoints, dy: payload.scrollYPoints)
        }
    }

    private func applyClick(_ click: Click) async {
        let button = mapButton(click.button)
        switch click.action {
        case .tap: await eventInjector.clickTap(button: button, clickCount: click.count)
        case .down: await eventInjector.click(button: button, isDown: true, clickCount: click.count)
        case .up: await eventInjector.click(button: button, isDown: false, clickCount: click.count)
        }
    }

    private func applyScrollPhase(_ phase: ScrollPhase) async {
        switch phase.phase {
        case .began:
            await eventInjector.scroll(phase: .began)
        case .ended:
            let velocity = Vector2(x: phase.vx ?? 0, y: phase.vy ?? 0)
            await eventInjector.scroll(phase: .ended, isMomentum: phase.momentum ?? true, liftVelocity: velocity)
        case .cancel:
            await eventInjector.scroll(phase: .cancel)
        }
    }

    private func applyKey(_ key: Key) async {
        let vk = UInt16(clamping: key.code)
        switch key.action {
        case .tap: await eventInjector.keyTap(virtualKey: vk, char: key.char, modifiers: key.modifiers)
        case .down: await eventInjector.key(virtualKey: vk, char: key.char, modifiers: key.modifiers, isDown: true)
        case .up: await eventInjector.key(virtualKey: vk, char: key.char, modifiers: key.modifiers, isDown: false)
        }
    }

    private func applyMediaKey(_ message: MediaKeyMessage) async {
        switch message.action {
        case .tap: await eventInjector.mediaKeyTap(message.key)
        case .down: await eventInjector.mediaKey(message.key, isDown: true)
        case .up: await eventInjector.mediaKey(message.key, isDown: false)
        }
    }

    private func mapButton(_ button: MouseButton) -> AirMouseProtocol.MouseButton { button }

    private func handleMacroInvoke(_ invoke: MacroInvoke, messageID: UInt32, sessionKey: String) async {
        guard let managed = sessions[sessionKey] else { return }
        let allowScripts: Bool
        if let fingerprint = managed.fingerprint, let record = await trustStore.lookup(fingerprint: fingerprint) {
            allowScripts = record.allowScripts
        } else {
            allowScripts = false
        }
        let globalEnabled = await globalScriptsEnabledProvider()
        var result = await macroEngine.invoke(
            invoke,
            from: managed.fingerprint?.hexString ?? sessionKey,
            deviceAllowsScripts: allowScripts,
            globalScriptsEnabled: globalEnabled
        )
        result.ref = messageID
        try? await managed.session.sendMacroResult(result)
    }

    private func broadcastMacroList(_ list: MacroList) async {
        for managed in sessions.values {
            let state = await managed.session.currentState
            guard state == .authenticated else { continue }
            try? await managed.session.sendMacroList(list)
        }
    }

    /// Pushes a fresh `hostState` to every authenticated session (spec §5.3.8/§5.3.9: "publishes
    /// `HostState` snapshots to `SessionManager`"). Call whenever `HostStateObserver`'s snapshot
    /// changes; polled once per ticker tick is also acceptable for callers that don't want to wire
    /// a push notification.
    public func broadcastHostStateIfChanged(_ snapshot: HostStateSnapshot) async {
        guard snapshot != lastHostState else { return }
        lastHostState = snapshot
        let globalScripts = await globalScriptsEnabledProvider()
        let hostState = Self.hostState(from: snapshot, sessionCount: sessions.count, globalScriptsEnabled: globalScripts)
        for managed in sessions.values {
            let state = await managed.session.currentState
            guard state == .authenticated else { continue }
            try? await managed.session.sendHostState(hostState)
        }
    }

    private static func hostState(from snapshot: HostStateSnapshot, sessionCount: Int, globalScriptsEnabled: Bool) -> HostState {
        HostState(
            paused: snapshot.isPaused,
            accessibility: snapshot.isAccessibilityTrusted,
            naturalScroll: snapshot.naturalScrollEnabled,
            displays: snapshot.displayTopology.displays.map { display in
                Display(
                    id: Int(display.id),
                    x: Int(display.bounds.origin.x),
                    y: Int(display.bounds.origin.y),
                    w: Int(display.bounds.width),
                    h: Int(display.bounds.height),
                    scale: 1,
                    main: display.isMain
                )
            },
            frontmostApp: snapshot.frontmostAppBundleID.map { FrontmostApp(bundleID: $0, name: $0) },
            inputSource: InputSource(id: "current", ansi: true),
            scriptsAllowed: globalScriptsEnabled,
            sessionCount: sessionCount
        )
    }

    // MARK: - --loopback JSON-lines event log

    private func drainLoopbackLog() async {
        guard let recordingPoster, let loopbackLogHandle else { return }
        let events = recordingPoster.events
        guard loopbackRecordedCount < events.count else { return }
        var buffer = Data()
        for posted in events[loopbackRecordedCount...] {
            if let line = Self.jsonLine(for: posted) {
                buffer.append(line)
                buffer.append(0x0A)
            }
        }
        loopbackRecordedCount = events.count
        guard !buffer.isEmpty else { return }
        try? loopbackLogHandle.write(contentsOf: buffer)
    }

    private static func jsonLine(for event: PostedEvent) -> Data? {
        var fields: [String: Any] = [
            "kind": kindName(event.kind),
            "location": ["x": event.location.x, "y": event.location.y],
            "timestamp": Date().timeIntervalSince1970,
        ]
        if let v = event.deltaX { fields["deltaX"] = v }
        if let v = event.deltaY { fields["deltaY"] = v }
        if let v = event.buttonNumber { fields["buttonNumber"] = v }
        if let v = event.clickState { fields["clickState"] = v }
        if let v = event.scrollWheel1 { fields["scrollWheel1"] = v }
        if let v = event.scrollWheel2 { fields["scrollWheel2"] = v }
        if let v = event.scrollPhase { fields["scrollPhase"] = v }
        if let v = event.keycode { fields["keycode"] = v }
        if let v = event.unicodeString { fields["unicodeString"] = v }
        if let v = event.nxKeyType { fields["nxKeyType"] = v }
        if let v = event.isKeyDown { fields["isKeyDown"] = v }
        return try? JSONSerialization.data(withJSONObject: fields, options: [])
    }

    /// Wire/log name for each `PostedEventKind` — kept identical to the enum's own case names
    /// (`Services/EventInjector/EventPosting.swift`, e.g. `.leftMouseDown`/`.systemDefinedKey`)
    /// rather than a shortened alias: this JSON is the `--loopback` contract the CLI/integration-test
    /// agent's suite parses (`LoopbackIntegrationTests.swift`'s `LoggedEventFields`), and that suite
    /// matches the exact case names (`"leftMouseDown"`, `"leftMouseUp"`, `"systemDefinedKey"`, …) —
    /// this used to emit `"leftDown"`/`"leftUp"`/`"mediaKey"` instead, a silent, deterministic
    /// mismatch that made every click/media-key assertion in that suite fail (never found, never a
    /// timing issue) regardless of whether the events were actually posted correctly.
    private static func kindName(_ kind: PostedEventKind) -> String {
        switch kind {
        case .mouseMoved: "mouseMoved"
        case .leftMouseDown: "leftMouseDown"
        case .leftMouseUp: "leftMouseUp"
        case .leftMouseDragged: "leftMouseDragged"
        case .rightMouseDown: "rightMouseDown"
        case .rightMouseUp: "rightMouseUp"
        case .rightMouseDragged: "rightMouseDragged"
        case .otherMouseDown: "otherMouseDown"
        case .otherMouseUp: "otherMouseUp"
        case .otherMouseDragged: "otherMouseDragged"
        case .scrollWheel: "scrollWheel"
        case .keyDown: "keyDown"
        case .keyUp: "keyUp"
        case .systemDefinedKey: "systemDefinedKey"
        case .other: "other"
        }
    }
}
