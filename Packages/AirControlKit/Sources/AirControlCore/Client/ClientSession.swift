import Foundation
import AirControlProtocol
import AirControlCrypto
import AirControlFilters

/// Drives one full client-side session over injected `ControlChannel`/`DatagramChannel`s: version
/// negotiation, pairing (proof/confirm using `PairingClient` and the TLS exporter or the §3.2.3
/// contingency), trusted reconnect, `sessionKey` installation, motion sending (UDP normally,
/// `MotionBatch` over TCP when `ProbeController` says the UDP path looks unhealthy), every C→H
/// control message, and delivery of H→C events via `events`.
///
/// **Deviation from `DatagramChannel`'s two required protocols**: the UDP port to connect to is
/// only known once `helloAck.udpPort` arrives, and this module never imports `Network`, so it
/// cannot open that connection itself. `datagramProvider` is the seam: the app supplies a closure
/// that opens a `DatagramChannel` to the already-known host address at the given port. See the
/// final report for this call.
///
/// An `actor` (not a pure reducer) because it owns real mutable session state — install keys,
/// counters, in-flight handshake continuations, two concurrent receive loops — shared across
/// concurrent callers (the app's send calls and the two receive loops); arch §3.1's "no actors in
/// the kit" principle is the default for the pure state machines, but the assignment for this
/// module explicitly calls for `ClientSession`/`HostSession` actors, and Swift's actor isolation is
/// the natural way to make this state race-free without hand-rolled locks.
public actor ClientSession {
    private let control: any ControlChannel
    private let datagramProvider: DatagramChannelProvider
    private let clock: any Clock
    private let localFingerprint: Fingerprint
    private let device: Hello.Device
    private let displayHz: Int
    private let capabilities: [Capability]

    public nonisolated let events: AsyncStream<ClientEvent>
    private let eventsContinuation: AsyncStream<ClientEvent>.Continuation

    private var frameDecoder = FrameDecoder()
    private var receiveTask: Task<Void, Never>?
    private var datagramTask: Task<Void, Never>?
    private var datagramChannel: (any DatagramChannel)?

    private var negotiatedVersion: Int = ProtocolConstants.protocolVersion
    private var udpPort: Int?
    private var sessionID: UInt32?
    private var directionalKeys: SessionKeys.DirectionalKeys?
    private var c2hCounter: UInt64 = 0
    private var h2cReplayWindow = ReplayWindow()
    private var envelopeIDCounter: UInt32 = 0
    private var isClosed = false

    /// Whichever of `pairChallenge` (normal first-time/re- pairing) or `helloAck` (spec decision,
    /// not in §3.2/§3.3: the host may skip straight to `helloAck` when it already trusts this
    /// peer's certificate — see `HostSessionStateMachine`'s `.tlsAccepted(.known)`/
    /// `.helloReceivedPairingTrue` case, and `HostSession.beginPairingChallenge`) arrives first in
    /// response to `hello { pairing: true }`. A single actor-isolated waiter rather than two
    /// continuations raced via a `TaskGroup`: `PendingReply` is deliberately not internally
    /// synchronized (see its own doc comment), and racing two unstructured child tasks each
    /// calling `.await()`/`.deliver()` concurrently with this actor's own message handling would
    /// break that single-actor-access invariant.
    private let firstPairingReply = PendingReply<FirstPairingReply>()
    private let pairConfirmReply = PendingReply<PairConfirm>()
    private let helloAckReply = PendingReply<HelloAck>()
    private let sessionKeyReply = PendingReply<Void>()

    private var probeController = ProbeController()
    private var previousProbeMode: ProbeController.Mode = .normal
    private var outstandingProbeTimestamp: UInt32?
    private var pendingMotionBatch: [MotionPayload] = []

    private var heartbeatClock = HeartbeatClock()
    private var statsCollector = SessionStatsCollector()
    private var heartbeatSeq: Int = 0
    private var lastPongAt: TimeInterval?

    public init(
        control: any ControlChannel,
        datagramProvider: @escaping DatagramChannelProvider,
        clock: any Clock,
        localFingerprint: Fingerprint,
        device: Hello.Device,
        displayHz: Int = 60,
        capabilities: [Capability] = [.tcpMotionFallback, .udpProbe, .unicodeText, .macroScripts]
    ) {
        self.control = control
        self.datagramProvider = datagramProvider
        self.clock = clock
        self.localFingerprint = localFingerprint
        self.device = device
        self.displayHz = displayHz
        self.capabilities = capabilities
        var continuation: AsyncStream<ClientEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventsContinuation = continuation
    }

    /// Starts the control-channel receive loop, if not already running. Actor initializers cannot
    /// spawn a `Task` that captures `self` (strict concurrency forbids touching actor-isolated
    /// storage from a non-async `init` once such a closure exists), so this is called lazily by
    /// `connect(...)`/`pair(...)` — the two entry points that must be called before anything else
    /// is useful anyway.
    private func ensureReceiveLoopStarted() {
        guard receiveTask == nil else { return }
        receiveTask = Task { [weak self] in
            await self?.runReceiveLoop()
        }
    }

    // MARK: - Connect / pair

    /// Trusted reconnect (spec §3.3.1): sends `hello { pairing: false }`, waits for `helloAck` and
    /// the `sessionKey` that follows it, and returns once the motion channel is ready.
    public func connect(macroRevision: Int? = nil) async throws -> ConnectedInfo {
        ensureReceiveLoopStarted()
        try await sendHello(pairing: false, macroRevision: macroRevision)
        let ack = try await helloAckReply.await()
        try await sessionKeyReply.await()
        return ConnectedInfo(ack: ack)
    }

    /// First-time pairing (spec §3.2.2): `hello { pairing: true }` → `pairChallenge` → compute and
    /// send `pairProof` (via `PairingClient`, using the TLS exporter or the zero-exporter
    /// contingency) → verify `pairConfirm.hostProof` → `helloAck` + `sessionKey`.
    public func pair(url: PairingURL, macroRevision: Int? = nil) async throws -> ConnectedInfo {
        guard let hostFingerprint = Fingerprint(bytes: Array(url.fingerprint)) else {
            throw CoreError.internalFailure("pairing URL fingerprint is not 32 bytes")
        }
        ensureReceiveLoopStarted()
        try await sendHello(pairing: true, macroRevision: macroRevision)

        // spec decision (§3.2/§3.3 don't define this): a host that already trusts this peer's
        // certificate may answer a re-pairing `hello { pairing: true }` with `helloAck` directly,
        // never sending `pairChallenge` at all (see `HostSessionStateMachine`). This used to hang
        // forever waiting only on `pairChallenge` — see `firstPairingReply`'s doc comment — until
        // the host's own no-heartbeat watchdog closed the connection out from under it, surfacing
        // as a bare "internal" error. Handle whichever answer actually arrives.
        switch try await firstPairingReply.await() {
        case .alreadyTrusted(let ack):
            // No proof round trip happened in this branch, so the TLS peer's fingerprint — not
            // this QR's claimed fingerprint, which nothing here cryptographically checked — is
            // the only one anything actually verified.
            let trustedFingerprint = await control.peerFingerprint ?? hostFingerprint
            eventsContinuation.yield(.paired(hostFingerprint: trustedFingerprint))
            try await sessionKeyReply.await()
            return ConnectedInfo(ack: ack)

        case .challenge(let challenge):
            let exporter = await control.exporterSecret()
            let proof = try PairingClient.computeProof(
                secret: url.secret,
                exporter: exporter,
                nonce: challenge.nonce.data,
                clientFingerprint: localFingerprint,
                hostFingerprint: hostFingerprint,
                hostID: challenge.hostID.data
            )
            try await send(.pairProof(PairProof(proof: B64UData(proof))))
            let confirm = try await pairConfirmReply.await()
            let verified = try PairingClient.verifyHostProof(
                confirm.hostProof.data,
                secret: url.secret,
                exporter: exporter,
                nonce: challenge.nonce.data,
                clientFingerprint: localFingerprint,
                hostFingerprint: hostFingerprint,
                hostID: challenge.hostID.data
            )
            guard verified else { throw CoreError.pairingHostProofInvalid }
            eventsContinuation.yield(.paired(hostFingerprint: hostFingerprint))

            let ack = try await helloAckReply.await()
            try await sessionKeyReply.await()
            return ConnectedInfo(ack: ack)
        }
    }

    private func sendHello(pairing: Bool, macroRevision: Int?) async throws {
        let hello = Hello(
            protocol: .init(min: ProtocolConstants.protocolVersion, max: ProtocolConstants.protocolVersion),
            capabilities: capabilities.map(\.rawValue),
            device: device,
            pairing: pairing,
            macroRevision: macroRevision,
            displayHz: displayHz
        )
        try await send(.hello(hello))
    }

    // MARK: - Control message sends (spec §3.4.5)

    public func sendClick(_ click: Click) async throws { try await send(.click(click)) }
    public func sendScrollPhase(_ phase: ScrollPhase) async throws { try await send(.scrollPhase(phase)) }
    public func sendModifiers(_ modifiers: Modifiers) async throws { try await send(.modifiers(modifiers)) }
    public func sendKey(_ key: Key) async throws { try await send(.key(key)) }
    public func sendText(_ text: Text) async throws { try await send(.text(text)) }
    public func sendDeleteBackward(_ deleteBackward: DeleteBackward) async throws { try await send(.deleteBackward(deleteBackward)) }
    public func sendMediaKey(_ mediaKey: MediaKeyMessage) async throws { try await send(.mediaKey(mediaKey)) }
    public func sendVolume(_ volume: Volume) async throws { try await send(.volume(volume)) }
    public func invokeMacro(id: UUID, confirmed: Bool) async throws { try await send(.macroInvoke(MacroInvoke(id: id, confirmed: confirmed))) }
    public func sendRecenter() async throws { try await send(.recenter) }
    public func sendMotionEndControl() async throws { try await send(.motionEnd) }
    public func sendSettings(_ settings: Settings) async throws { try await send(.settings(settings)) }

    /// spec §3.4.6: sent every `heartbeatMs` (500 by default) from `helloAck` onward. The app's own
    /// timer calls this on that cadence (arch §3.1: no timers inside the kit).
    public func sendHeartbeat() async throws {
        let seq = heartbeatSeq
        heartbeatSeq += 1
        let t1 = nowMicros()
        try await send(.heartbeat(Heartbeat(seq: seq, t1: t1)))
    }

    /// Sends one UDP probe (spec §3.5.8) — or, when in TCP fallback, still sends it (probes
    /// continue at 1 Hz per spec even while motion itself rides TCP). Resolves the previous
    /// outstanding probe as unanswered first if no echo arrived for it (the app's timer is the
    /// only source of "time has passed" in this actor, per arch §3.1: no timers in the kit).
    public func sendProbe() async throws {
        guard let sessionID, let keys = directionalKeys else { return }
        expireOutstandingProbeIfNeeded()
        // No UDP channel at all (never opened, or torn down): this is not "nothing to report" —
        // it is an unanswerable probe, so it must count as an immediate loss. Without this,
        // `ProbeController` never sees a single outcome and can never reach the ≥11-of-12 or
        // 8-straight-at-connect thresholds that engage TCP fallback (spec §3.5.8), leaving motion
        // silently stuck trying (and failing) to use a UDP path that will never come back.
        guard let channel = datagramChannel else {
            _ = recordProbeOutcome(answered: false)
            return
        }
        let timestamp = UInt32(truncatingIfNeeded: nowMicros())
        let payload = MotionPayload(flags: [.probe], source: .probe, samples: 0, timestamp: timestamp)
        var output = [UInt8](repeating: 0, count: MotionCrypto.datagramLength)
        try MotionCrypto.seal(
            payload: Array(payload.encoded()),
            sessionID: sessionID,
            counter: c2hCounter,
            key: keys.clientToHost,
            into: &output
        )
        c2hCounter += 1
        do {
            try channel.send(Data(output))
        } catch {
            // Same reasoning as the nil-channel case above: a send that throws must still be
            // recorded as a loss rather than propagating out of `sendProbe()` (the app's ticker
            // calls this with `try?`, which would otherwise swallow it with no outcome recorded
            // at all).
            _ = recordProbeOutcome(answered: false)
            return
        }
        outstandingProbeTimestamp = timestamp
    }

    /// If a probe is still outstanding (no echo since it was sent), records it as unanswered. A
    /// caller with its own timeout timer may call this directly instead of waiting for the next
    /// `sendProbe()` to implicitly do so.
    @discardableResult
    public func expireOutstandingProbeIfNeeded() -> ProbeController.Mode {
        guard outstandingProbeTimestamp != nil else { return probeController.mode }
        outstandingProbeTimestamp = nil
        return recordProbeOutcome(answered: false)
    }

    private func recordProbeOutcome(answered: Bool) -> ProbeController.Mode {
        let pongRecent = lastPongAt.map { clock.now() - $0 <= 1.0 } ?? false
        let mode = probeController.recordProbeOutcome(answered: answered, pongSeenWithinLastSecond: pongRecent)
        statsCollector.recordProbeOutcome(answered: answered, pongSeenWithinLastSecond: pongRecent)
        if mode != previousProbeMode {
            eventsContinuation.yield(mode == .fallback ? .fallbackEngaged : .fallbackRecovered)
            previousProbeMode = mode
        }
        return mode
    }

    public func sendGoodbye(_ reason: GoodbyeReason) async throws {
        try await send(.goodbye(Goodbye(reason: reason)))
    }

    // MARK: - Motion (spec §3.5)

    /// Seals and sends one motion sample, or — while `ProbeController` reports `.fallback` —
    /// accumulates it into a `MotionBatch` flushed at up to `MotionBatch.maxPayloadsPerFrame`
    /// payloads per frame (spec §3.5.8/§3.5.9). Coalescing frame *rate* (≤ 60 fps) in fallback is
    /// the caller's responsibility (it owns the touch/gyro sampling timer); this only bounds
    /// payloads *per frame*.
    public func sendMotion(_ payload: MotionPayload) async throws {
        guard let sessionID, let keys = directionalKeys else { throw CoreError.channelClosed }
        if probeController.mode == .fallback {
            pendingMotionBatch.append(payload)
            if pendingMotionBatch.count >= MotionBatch.maxPayloadsPerFrame {
                try await flushPendingMotionBatch()
            }
        } else {
            guard let channel = datagramChannel else { throw CoreError.channelClosed }
            var output = [UInt8](repeating: 0, count: MotionCrypto.datagramLength)
            try MotionCrypto.seal(
                payload: Array(payload.encoded()),
                sessionID: sessionID,
                counter: c2hCounter,
                key: keys.clientToHost,
                into: &output
            )
            c2hCounter += 1
            try channel.send(Data(output))
        }
        statsCollector.recordMotionAccepted(now: clock.now())
    }

    /// Flushes any accumulated TCP-fallback motion batch as one `kind = 0x02` frame. The app's own
    /// pacing timer calls this at up to 60 Hz while in fallback (spec §3.5.8).
    public func flushPendingMotionBatch() async throws {
        guard !pendingMotionBatch.isEmpty else { return }
        let payloads = pendingMotionBatch
        pendingMotionBatch.removeAll()
        let body = try MotionBatch.encode(payloads)
        let frame = try FrameEncoder.encode(kind: .motionBatch, body: body)
        try await control.send(frame)
    }

    public func currentStats() -> SessionStats {
        statsCollector.snapshot(now: clock.now())
    }

    // MARK: - Lifecycle

    public func close(reason: GoodbyeReason = .userQuit) async {
        if !isClosed {
            try? await send(.goodbye(Goodbye(reason: reason)))
        }
        await teardown(reason: "closed:\(reason.rawValue)")
    }

    private func teardown(reason: String) async {
        guard !isClosed else { return }
        isClosed = true
        receiveTask?.cancel()
        datagramTask?.cancel()
        datagramChannel?.close()
        await control.close()
        failAllWaiters(with: CoreError.channelClosed)
        eventsContinuation.yield(.disconnected(reason: reason))
        eventsContinuation.finish()
    }

    private func failAllWaiters(with error: Error) {
        firstPairingReply.fail(error)
        pairConfirmReply.fail(error)
        helloAckReply.fail(error)
        sessionKeyReply.fail(error)
    }

    // MARK: - Sending helpers

    private func send(_ message: Message) async throws {
        let envelope = Envelope(v: negotiatedVersion, i: nextEnvelopeID(), message: message)
        let body = try WireCoding.encodeEnvelope(envelope)
        let frame = try FrameEncoder.encode(kind: .json, body: body)
        try await control.send(frame)
    }

    private func nextEnvelopeID() -> UInt32 {
        defer { envelopeIDCounter &+= 1 }
        return envelopeIDCounter
    }

    private func nowMicros() -> Int64 {
        Int64((clock.now() * 1_000_000).rounded())
    }

    // MARK: - Control receive loop

    private func runReceiveLoop() async {
        do {
            for try await data in control.incoming {
                await handleIncomingControlData(data)
            }
            await teardown(reason: "control channel finished")
        } catch {
            await teardown(reason: "control channel error: \(error)")
        }
    }

    private func handleIncomingControlData(_ data: Data) async {
        let frames: [Frame]
        do {
            frames = try frameDecoder.feed(data)
        } catch {
            await teardown(reason: "frame decode error: \(error)")
            return
        }
        for frame in frames {
            guard frame.kind == .json else { continue } // client never receives motion-batch frames
            do {
                let envelope = try WireCoding.decodeEnvelope(frame.body)
                await handle(message: envelope.message)
            } catch {
                continue // spec §3.4.2: drop malformed message, don't close
            }
        }
    }

    private func handle(message: Message) async {
        switch message {
        case .pairChallenge(let challenge):
            eventsContinuation.yield(.pairingChallengeReceived(hostName: challenge.hostName))
            firstPairingReply.deliver(.challenge(challenge))
        case .pairConfirm(let confirm):
            pairConfirmReply.deliver(confirm)
        case .helloAck(let ack):
            negotiatedVersion = ack.protocol
            udpPort = ack.udpPort
            helloAckReply.deliver(ack)
            // Only meaningful to a `pair(url:)` still waiting on `firstPairingReply` (the
            // already-trusted shortcut); harmless — buffered and never read — for `connect()` or
            // for the `helloAck` that follows a normal `pairConfirm` in `pair(url:)`'s other
            // branch, both of which never touch this slot.
            firstPairingReply.deliver(.alreadyTrusted(ack))
            eventsContinuation.yield(.connected(ConnectedInfo(ack: ack)))
        case .sessionKey(let key):
            await installSessionKey(key)
        case .hostState(let state):
            eventsContinuation.yield(.hostState(state))
        case .macroList(let list):
            eventsContinuation.yield(.macroList(list))
        case .macroResult(let result):
            eventsContinuation.yield(.macroResult(result))
        case .pong(let pong):
            handlePong(pong)
        case .error(let payload):
            eventsContinuation.yield(.error(payload))
            let error = CoreError(wire: payload)
            failAllWaiters(with: error)
            if payload.fatal {
                await teardown(reason: "fatal error \(payload.code)")
            }
        case .goodbye(let goodbye):
            eventsContinuation.yield(.goodbye(goodbye.reason))
            await teardown(reason: "goodbye:\(goodbye.reason.rawValue)")
        default:
            break // C→H-only or unknown message types are never sent to a client
        }
    }

    private func handlePong(_ pong: Pong) {
        lastPongAt = clock.now()
        let t4 = nowMicros()
        heartbeatClock.recordRoundTrip(t1: pong.t1, t2: pong.t2, t3: pong.t3, t4: t4)
        statsCollector.recordHeartbeatRoundTrip(t1: pong.t1, t2: pong.t2, t3: pong.t3, t4: t4)
    }

    private func installSessionKey(_ message: SessionKeyMessage) async {
        guard let secret = SessionSecret(data: message.secret.data) else {
            sessionKeyReply.fail(CoreError.protocolMismatch(
                expected: "a \(SessionSecret.byteCount)-byte session secret",
                got: "\(message.secret.data.count) bytes"
            ))
            return
        }
        let keys = SessionKeys.derive(secret: secret, sessionID: message.sessionID)
        sessionID = message.sessionID
        directionalKeys = keys
        c2hCounter = 0
        h2cReplayWindow = ReplayWindow()
        probeController.reset()
        previousProbeMode = .normal
        outstandingProbeTimestamp = nil
        pendingMotionBatch.removeAll()

        do {
            let channel = try await datagramProvider(udpPort ?? 0)
            datagramChannel = channel
            startDatagramReceiveLoop(channel)
            sessionKeyReply.deliver(())
        } catch {
            sessionKeyReply.fail(error)
        }
    }

    // MARK: - Datagram (UDP) receive loop

    private func startDatagramReceiveLoop(_ channel: any DatagramChannel) {
        datagramTask?.cancel()
        datagramTask = Task { [weak self] in
            for await data in channel.incoming {
                await self?.handleIncomingDatagram(data)
            }
        }
    }

    private func handleIncomingDatagram(_ data: Data) async {
        guard let keys = directionalKeys else { return }
        var window = h2cReplayWindow
        let result = MotionCrypto.openAuthenticated(
            datagram: Array(data),
            resolveKey: { _ in keys.hostToClient },
            window: &window
        )
        h2cReplayWindow = window
        guard case .success(let plaintext) = result,
              let payload = MotionPayload(data: Data(plaintext)),
              payload.flags.contains(.echo)
        else { return }
        outstandingProbeTimestamp = nil
        _ = recordProbeOutcome(answered: true)
    }
}

/// Whichever message actually answers `hello { pairing: true }` first — see `ClientSession.
/// firstPairingReply`'s doc comment for why this is one waiter instead of racing two.
private enum FirstPairingReply: Sendable {
    case challenge(PairChallenge)
    case alreadyTrusted(HelloAck)
}

/// A single in-flight "waiting for exactly one reply of type `T`" slot, safe against the reply
/// arriving before anyone is waiting for it.
///
/// The naive version of this — an array of `CheckedContinuation`s that a caller appends to and the
/// message handler drains on arrival — has a lost-wakeup race: `send(_:)` crosses into the injected
/// `ControlChannel` actor, so it's a genuine suspension point, and `HostSession` can answer (and, in
/// a burst like pairing's `pairConfirm` → `helloAck` → `sessionKey`, answer *several* messages in a
/// row) before the caller's task resumes far enough to register its continuation — at which point
/// the reply has already been drained into an empty waiters array and is gone, and the caller hangs
/// forever. `PendingReply` closes that window by also remembering a reply that arrived with nobody
/// waiting, so a caller that shows up later gets it immediately instead of waiting for a message
/// that already came and went.
///
/// Only ever touched from `ClientSession`'s actor-isolated methods, so `@unchecked Sendable` here
/// just asserts single-threaded access rather than doing any locking of its own.
private final class PendingReply<T: Sendable>: @unchecked Sendable {
    private enum State {
        case idle
        case waiting(CheckedContinuation<T, Error>)
        case ready(Result<T, Error>)
    }

    private var state: State = .idle

    /// Waits for the next reply — resolving immediately if one already arrived (and was buffered)
    /// before this was called.
    func await() async throws -> T {
        if case .ready(let result) = state {
            state = .idle
            return try result.get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            state = .waiting(continuation)
        }
    }

    /// Delivers a successful reply: resumes whoever's waiting, or buffers it for the next `await()`.
    func deliver(_ value: T) {
        settle(.success(value))
    }

    /// Fails the pending reply: resumes whoever's waiting with `error`, or buffers the failure for
    /// the next `await()`.
    func fail(_ error: Error) {
        settle(.failure(error))
    }

    private func settle(_ result: Result<T, Error>) {
        switch state {
        case .waiting(let continuation):
            state = .idle
            continuation.resume(with: result)
        case .idle, .ready:
            // Overwrite rather than queue: this protocol never expects more than one outstanding
            // reply of a given kind at a time.
            state = .ready(result)
        }
    }
}
