import Foundation
import Security
import AirControlProtocol
import AirControlCrypto
import AirControlFilters

/// Drives one accepted connection host-side: mirrors `ClientSession` (spec §3.2, §3.3, §3.4,
/// §3.5). Handles `hello`, issues `sessionKey`, verifies a pairing proof against a
/// `PairingWindow`, opens the motion receive path (`MotionCrypto` + `ReplayWindow` + the "> 8
/// behind" stale-apply rule, and probe reflection), emits `HostEvent`s for the app's
/// `EventInjector`, and answers heartbeats with `pong`.
///
/// Same actor-vs-pure-reducer note as `ClientSession`: owns real concurrent mutable state (keys,
/// counters, two receive loops, held-input ledger), hence an `actor` per the assignment even
/// though arch §3.1's default for the kit is pure reducers.
public actor HostSession {
    /// Everything the host needs to know about itself to answer `hello`/pairing, independent of
    /// any one connection.
    public struct HostIdentity: Sendable {
        public var hostID: Data // 16 bytes
        public var name: String
        public var model: String
        public var os: String
        public var helperVersion: String
        public var fingerprint: Fingerprint

        public init(hostID: Data, name: String, model: String, os: String, helperVersion: String, fingerprint: Fingerprint) {
            self.hostID = hostID
            self.name = name
            self.model = model
            self.os = os
            self.helperVersion = helperVersion
            self.fingerprint = fingerprint
        }
    }

    private let control: any ControlChannel
    private let clock: any Clock
    private let identity: HostIdentity
    private let capabilities: [Capability]
    private let udpPort: Int
    /// The pairing window this connection may prove against — handed in regardless of
    /// `peerKnowledge` (spec decision: a known peer's `hello { pairing: true }` still needs it,
    /// see `initialPeerKnowledge`'s doc comment) and consulted only if `hello.pairing == true`.
    private var pairingWindow: PairingWindow?
    /// `peerKnowledge` as observed at TLS accept time, kept independently of `state` (which loses
    /// it once the state machine moves into `.pairing`) — `beginPairingChallenge()` needs it to
    /// pick the right error when a known peer's re-pairing attempt finds no open window
    /// (`pairing.alreadyTrusted` rather than the unknown-peer `pairing.expired` wording).
    private let initialPeerKnowledge: HostPeerKnowledge
    private var currentMacroRevision: Int
    private var currentHostState: HostState
    private var currentMacros: [Macro]

    public nonisolated let events: AsyncStream<HostEvent>
    private let eventsContinuation: AsyncStream<HostEvent>.Continuation

    private var state: HostSessionState
    private var frameDecoder = FrameDecoder()
    private var receiveTask: Task<Void, Never>?
    private var datagramChannel: (any DatagramChannel)?
    private var datagramTask: Task<Void, Never>?

    private var negotiatedVersion: Int = ProtocolConstants.protocolVersion
    private var sessionID: UInt32?
    private var directionalKeys: SessionKeys.DirectionalKeys?
    private var h2cCounter: UInt64 = 0
    private var c2hReplayWindow = ReplayWindow()
    /// Highest UDP motion counter whose deltas were actually applied (spec §3.5.4's separate
    /// "> 8 behind" stale-apply rule, distinct from the 64-wide replay window).
    private var highestAppliedCounter: UInt64 = 0
    private var envelopeIDCounter: UInt32 = 0
    private var isClosed = false

    private var rateLimiter = RateLimiter()
    private var heldInputs = HeldInputLedger()
    private var badMessageTimestamps: [TimeInterval] = []

    /// The most recent accepted motion datagram's client timestamp/host receive time, for
    /// `pong.motion` (spec §3.4.5).
    private var lastMotion: (clientTs: Int64, hostTs: Int64)?

    /// `pairChallenge`'s nonce, the client's fingerprint, and the exporter, held between
    /// `hello{pairing:true}` and the matching `pairProof`.
    private var pendingPairing: (nonce: Data, clientFingerprint: Fingerprint, exporter: Data?)?
    /// The `hello{pairing:true}` device info, held so a completed pairing can still emit
    /// `.clientAuthenticated(device:)` — a pairing flow has only the one `hello`, never a second
    /// one at proof time, unlike a trusted reconnect where `hello.device` is available directly
    /// in `handleHello`.
    private var pendingHelloDevice: Hello.Device?

    public init(
        control: any ControlChannel,
        clock: any Clock,
        identity: HostIdentity,
        peerKnowledge: HostPeerKnowledge,
        pairingWindow: PairingWindow?,
        hostState: HostState,
        macros: [Macro] = [],
        macroRevision: Int = 0,
        udpPort: Int = ProtocolConstants.defaultUDPPort,
        capabilities: [Capability] = [.tcpMotionFallback, .udpProbe, .unicodeText, .macroScripts]
    ) {
        self.control = control
        self.clock = clock
        self.identity = identity
        self.pairingWindow = pairingWindow
        self.initialPeerKnowledge = peerKnowledge
        self.currentHostState = hostState
        self.currentMacros = macros
        self.currentMacroRevision = macroRevision
        self.udpPort = udpPort
        self.capabilities = capabilities
        self.state = .tlsAccepted(peer: peerKnowledge)
        var continuation: AsyncStream<HostEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventsContinuation = continuation
    }

    // MARK: - Lifecycle

    /// Starts consuming the control channel. Must be called once, after construction.
    public func start() {
        guard receiveTask == nil else { return }
        receiveTask = Task { [weak self] in
            await self?.runReceiveLoop()
        }
    }

    /// Attaches the motion (UDP) channel already bound for this session's `sessionID` (the app
    /// owns the actual `NWListener`/per-session `NWConnection`; `AirControlCore` never imports
    /// `Network`). Safe to call any time after `sessionID` is known (i.e. after authentication).
    public func attachDatagramChannel(_ channel: any DatagramChannel) {
        datagramChannel?.close()
        datagramChannel = channel
        datagramTask?.cancel()
        datagramTask = Task { [weak self] in
            for await data in channel.incoming {
                await self?.handleIncomingDatagram(data)
            }
        }
    }

    public var currentState: HostSessionState { state }
    public var currentSessionID: UInt32? { sessionID }

    public func close(reason: GoodbyeReason = .hostQuit) async {
        if !isClosed {
            try? await send(.goodbye(Goodbye(reason: reason)))
        }
        await teardown()
    }

    private func teardown() async {
        guard !isClosed else { return }
        isClosed = true
        receiveTask?.cancel()
        datagramTask?.cancel()
        datagramChannel?.close()
        await control.close()
        rateLimiter.removeSession(sessionKey: "session")
        let released = heldInputs.releaseAll()
        if !released.isEmpty {
            eventsContinuation.yield(.releaseHeldInputs(released))
        }
        eventsContinuation.yield(.clientDisconnected(reason: "closed"))
        eventsContinuation.finish()
    }

    // MARK: - Outgoing (H→C, spec §3.4.5)

    public func sendHostState(_ hostState: HostState) async throws {
        currentHostState = hostState
        try await send(.hostState(hostState))
    }

    public func sendMacroList(_ list: MacroList) async throws {
        currentMacros = list.macros
        currentMacroRevision = list.revision
        try await send(.macroList(list))
    }

    public func sendMacroResult(_ result: MacroResult) async throws {
        try await send(.macroResult(result))
    }

    public func sendError(_ payload: ErrorPayload) async throws {
        try await send(.error(payload))
        if payload.fatal {
            await teardown()
        }
    }

    // MARK: - Heartbeat timing / stale / watchdog (spec §3.4.6, §5.3.11)

    /// Call periodically (the app's own timer). Marks the session `stale` at 2 s without a
    /// `heartbeat`, closes at 6 s, and force-releases any held input past the 60 s watchdog.
    public func checkTimeouts(now: TimeInterval, lastHeartbeatAt: TimeInterval) async {
        let elapsed = now - lastHeartbeatAt
        if elapsed >= Double(ProtocolConstants.sessionCloseTimeoutMs) / 1000.0 {
            await perform(apply(.noHeartbeatFor6s))
        } else if elapsed >= Double(ProtocolConstants.sessionStaleTimeoutMs) / 1000.0, state == .authenticated {
            await perform(apply(.noHeartbeatFor2s))
        }
        let watchdogItems = heldInputs.itemsExceedingWatchdog(now: now)
        if !watchdogItems.isEmpty {
            heldInputs.release(watchdogItems)
            eventsContinuation.yield(.releaseHeldInputs(watchdogItems))
        }
    }

    /// Records that `item` is now held (spec §5.3.11) — the app's `EventInjector` calls this after
    /// posting a "down" event so `HostSession` can release it on stale/watchdog/close.
    public func recordHeldInputDown(_ item: HeldInputItem) {
        heldInputs.recordDown(item, now: clock.now())
    }

    /// Records that `item` is no longer held.
    public func recordHeldInputUp(_ item: HeldInputItem) {
        heldInputs.recordUp(item)
    }

    // MARK: - State machine glue

    /// Mutates `state` per `HostSessionStateMachine.reduce` and returns the effects to perform.
    /// Synchronous by design (arch §3.1: the reducer itself is pure) — `perform(_:)` does the
    /// actual async work (sending, tearing down).
    @discardableResult
    private func apply(_ event: HostSessionEvent) -> [HostSessionEffect] {
        let (newState, effects) = HostSessionStateMachine.reduce(state: state, event: event)
        state = newState
        return effects
    }

    private func perform(_ effects: [HostSessionEffect]) async {
        for effect in effects {
            switch effect {
            case .releaseHeldInputsAndMarkStale:
                let released = heldInputs.releaseAll()
                if !released.isEmpty {
                    eventsContinuation.yield(.releaseHeldInputs(released))
                }
            case .restoreFromStale, .beginPairingFlow, .completeAuthentication:
                break // handled explicitly by the caller, which has the context (hello/proof) apply() doesn't
            case .closeConnection:
                await teardown()
            case .sendAuthUntrustedAndClose:
                try? await send(.error(ErrorPayload(code: .authUntrusted, message: "not authenticated", fatal: true)))
                await teardown()
            case .sendPairingErrorAndClose:
                try? await send(.error(ErrorPayload(code: .pairingInvalidProof, message: "pairing failed", fatal: true)))
                await teardown()
            }
        }
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
            await teardown()
        } catch {
            await teardown()
        }
    }

    private func handleIncomingControlData(_ data: Data) async {
        let frames: [Frame]
        do {
            frames = try frameDecoder.feed(data)
        } catch {
            try? await send(.error(ErrorPayload(code: .badFrame, message: "\(error)", fatal: true)))
            await teardown()
            return
        }
        for frame in frames {
            switch frame.kind {
            case .json:
                await handleJSONFrame(frame.body)
            case .motionBatch:
                await handleMotionBatchFrame(frame.body)
            }
            if isClosed { return }
        }
    }

    private func handleJSONFrame(_ body: Data) async {
        let envelope: Envelope
        do {
            envelope = try WireCoding.decodeEnvelope(body)
        } catch {
            recordBadMessage()
            return
        }

        // spec §7.6: control messages ≤ 200/s per session, burst 400.
        guard rateLimiter.allowControlMessage(sessionKey: "session", now: clock.now()) else {
            try? await send(.error(ErrorPayload(code: .rateLimited, message: "rate limit exceeded", fatal: true)))
            await teardown()
            return
        }

        // spec §3.2.1/§3.2.6: while unauthenticated, only hello/pairProof is accepted.
        switch state {
        case .tlsAccepted(.unknown), .pairing:
            switch envelope.message {
            case .hello, .pairProof:
                break
            default:
                await perform(apply(.nonPairMessageWhileUnauthenticated))
                return
            }
        default:
            break
        }

        await handle(message: envelope.message, envelopeID: envelope.i)
    }

    private func recordBadMessage() {
        let now = clock.now()
        badMessageTimestamps.append(now)
        badMessageTimestamps.removeAll { now - $0 > 10 }
        if badMessageTimestamps.count >= 3 {
            Task { [weak self] in
                try? await self?.send(.error(ErrorPayload(code: .badMessage, message: "too many malformed messages", fatal: true)))
                await self?.teardown()
            }
        }
    }

    private func handle(message: Message, envelopeID: UInt32) async {
        switch message {
        case .hello(let hello):
            await handleHello(hello)
        case .pairProof(let proof):
            await handlePairProof(proof)
        case .settings(let settings):
            eventsContinuation.yield(.settings(settings))
        case .click(let click):
            eventsContinuation.yield(.click(click))
        case .scrollPhase(let phase):
            eventsContinuation.yield(.scrollPhase(phase))
        case .modifiers(let modifiers):
            eventsContinuation.yield(.modifiers(modifiers))
        case .key(let key):
            eventsContinuation.yield(.key(key))
        case .text(let text):
            eventsContinuation.yield(.text(text))
        case .deleteBackward(let deleteBackward):
            eventsContinuation.yield(.deleteBackward(deleteBackward))
        case .mediaKey(let mediaKey):
            eventsContinuation.yield(.mediaKey(mediaKey))
        case .volume(let volume):
            eventsContinuation.yield(.volume(volume))
        case .macroInvoke(let invoke):
            eventsContinuation.yield(.macroInvoke(invoke, messageID: envelopeID))
        case .recenter:
            eventsContinuation.yield(.recenter)
        case .motionEnd:
            eventsContinuation.yield(.motion(MotionDeltaEvent(
                payload: MotionPayload(flags: [.motionEnd], source: .touch, samples: 0, timestamp: UInt32(truncatingIfNeeded: nowMicros())),
                channel: .tcp,
                shouldApply: true
            )))
        case .heartbeat(let heartbeat):
            await handleHeartbeat(heartbeat)
        case .goodbye(let goodbye):
            eventsContinuation.yield(.clientDisconnected(reason: goodbye.reason.rawValue))
            await perform(apply(.goodbyeReceived))
        default:
            break // H→C-only or unknown message types are never sent by a client
        }
    }

    private func handleHeartbeat(_ heartbeat: Heartbeat) async {
        await perform(apply(.heartbeatReceived))
        let t2 = nowMicros()
        let t3 = nowMicros()
        let pong = Pong(
            seq: heartbeat.seq,
            t1: heartbeat.t1,
            t2: t2,
            t3: t3,
            motion: lastMotion.map { Pong.MotionTiming(clientTs: $0.clientTs, hostTs: $0.hostTs) },
            injectP50Us: nil
        )
        try? await send(.pong(pong))
    }

    // MARK: - Hello / version negotiation (spec §3.4.4)

    private func handleHello(_ hello: Hello) async {
        guard let negotiated = ProtocolVersion.negotiate(
            clientMin: hello.protocol.min,
            clientMax: hello.protocol.max,
            hostMin: ProtocolConstants.protocolVersion,
            hostMax: ProtocolConstants.protocolVersion
        ) else {
            try? await send(.error(ErrorPayload(
                code: .versionMismatch,
                message: "no protocol version in common (client \(hello.protocol.min)...\(hello.protocol.max))",
                fatal: true
            )))
            await teardown()
            return
        }
        negotiatedVersion = negotiated.rawValue

        let effects = hello.pairing ? apply(.helloReceivedPairingTrue) : apply(.helloReceivedPairingFalse)
        await perform(effects)
        guard !isClosed else { return }

        switch state {
        case .pairing:
            pendingHelloDevice = hello.device
            await beginPairingChallenge()
        case .authenticated:
            await completeAuthentication(device: hello.device, macroRevision: hello.macroRevision, viaPairingFlow: false)
        default:
            break
        }
    }

    private func beginPairingChallenge() async {
        guard let window = pairingWindow, window.isOpen(now: Date(timeIntervalSince1970: clock.now())) else {
            // spec decision (§3.2/§3.3 don't define re-pairing an already-trusted device): a known
            // peer that re-scanned a pairing QR with no window open gets a distinct, clearer error
            // than an unknown peer would — from a device this Mac already trusts, "no pairing
            // window open" reads like pairing failed outright, when the actual fix is simply to
            // reconnect normally (spec §3.3.1) rather than scan again.
            if initialPeerKnowledge == .known {
                try? await send(.error(ErrorPayload(code: .alreadyTrusted, message: "already trusted; reconnect without pairing", fatal: true)))
            } else {
                try? await send(.error(ErrorPayload(code: .pairingExpired, message: "no pairing window open", fatal: true)))
            }
            await teardown()
            return
        }
        pairingWindow = window
        guard let peerFingerprint = await control.peerFingerprint else {
            try? await send(.error(ErrorPayload(code: .authUntrusted, message: "no peer certificate", fatal: true)))
            await teardown()
            return
        }
        let nonce = (try? SecureRandomBytes.generate(count: 16)) ?? Data(repeating: 0, count: 16)
        let exporter = await control.exporterSecret()
        pendingPairing = (nonce: nonce, clientFingerprint: peerFingerprint, exporter: exporter)
        let challenge = PairChallenge(
            nonce: B64UData(nonce),
            hostID: B64UData(identity.hostID),
            hostName: identity.name,
            expiresInMs: ProtocolConstants.pairingSecretLifetimeSeconds * 1000
        )
        try? await send(.pairChallenge(challenge))
    }

    private func handlePairProof(_ proof: PairProof) async {
        guard var window = pairingWindow, let pending = pendingPairing else {
            await perform(apply(.pairingFailed))
            try? await send(.error(ErrorPayload(code: .pairingExpired, message: "no pairing in progress", fatal: true)))
            await teardown()
            return
        }
        guard let binding = try? PairingWindow.binding(
            exporter: pending.exporter,
            nonce: pending.nonce,
            clientFingerprint: pending.clientFingerprint,
            hostFingerprint: identity.fingerprint,
            hostID: identity.hostID
        ) else {
            await perform(apply(.pairingFailed))
            try? await send(.error(ErrorPayload(code: .pairingInvalidProof, message: "malformed binding", fatal: true)))
            await teardown()
            return
        }
        let isValid = window.verifyClientProof(proof.proof.data, binding: binding)
        // Snapshot the host proof *before* `recordProofAttempt` mutates (and, on acceptance,
        // closes/consumes) the window — `computeHostProof` needs the secret that
        // `recordProofAttempt`'s internal `close()` zeroes out on the `.accepted` path.
        let hostProofIfAccepted = window.computeHostProof(binding: binding)
        let outcome = window.recordProofAttempt(valid: isValid, now: Date(timeIntervalSince1970: clock.now()))
        pairingWindow = window

        switch outcome {
        case .accepted:
            guard let hostProof = hostProofIfAccepted else {
                await perform(apply(.pairingFailed))
                await teardown()
                return
            }
            await perform(apply(.pairProofAccepted))
            try? await send(.pairConfirm(PairConfirm(hostProof: B64UData(hostProof), hostModel: identity.model)))
            guard !isClosed, state == .authenticated else { return }
            let device = pendingHelloDevice
            pendingPairing = nil
            pendingHelloDevice = nil
            await completeAuthentication(device: device, macroRevision: nil, viaPairingFlow: true)
        case .wrongProofRetry:
            try? await send(.error(ErrorPayload(code: .pairingInvalidProof, message: "invalid proof", fatal: false)))
        case .wrongProofLockedOut:
            await perform(apply(.pairingFailed))
            try? await send(.error(ErrorPayload(code: .pairingInvalidProof, message: "invalid proof, secret invalidated", fatal: true)))
            await teardown()
        case .rejected:
            await perform(apply(.pairingFailed))
            try? await send(.error(ErrorPayload(code: .pairingExpired, message: "pairing window expired", fatal: true)))
            await teardown()
        }
    }

    /// `device`/`macroRevision` are only known when this is reached from a `hello` (trusted
    /// reconnect, or the `hello{pairing:true}` that started a now-completed pairing flow); a
    /// completed pairing flow itself carries no second `hello`, so both are `nil` there and the
    /// macro list is always (re)sent.
    private func completeAuthentication(device: Hello.Device?, macroRevision: Int?, viaPairingFlow: Bool) async {
        if let device {
            eventsContinuation.yield(.clientAuthenticated(device: device, viaPairingFlow: viaPairingFlow))
        }
        let sendMacros = macroRevision == nil || macroRevision != currentMacroRevision
        // spec order (and `ClientSession.pair()`/`connect()`'s wait order) is `helloAck` *then*
        // `sessionKey`: the client only registers its `sessionKey` waiter after its `helloAck`
        // waiter resolves. Sending `sessionKey` first (as this used to) meant it could arrive and
        // be processed — silently, since nothing was waiting for it yet — before the client ever
        // registered that waiter, hanging `pair()`/`connect()` forever on a message that had
        // already come and gone.
        try? await send(.helloAck(HelloAck(
            protocol: negotiatedVersion,
            capabilities: capabilities.map(\.rawValue),
            host: HelloAck.Host(
                name: identity.name,
                model: identity.model,
                os: identity.os,
                helper: identity.helperVersion,
                id: B64UData(identity.hostID)
            ),
            udpPort: udpPort,
            heartbeatMs: ProtocolConstants.helloAckHeartbeatMsDefault,
            sessionTimeoutMs: ProtocolConstants.helloAckSessionTimeoutMsDefault,
            maxTextBytes: ProtocolConstants.helloAckMaxTextBytesDefault,
            sessionCount: 0
        )))
        await issueSessionKey()
        try? await send(.hostState(currentHostState))
        if sendMacros {
            try? await send(.macroList(MacroList(revision: currentMacroRevision, macros: currentMacros)))
        }
    }

    private func issueSessionKey() async {
        guard let secret = try? SessionSecret.generate() else { return }
        let newSessionID = UInt32.random(in: 1...UInt32.max)
        sessionID = newSessionID
        directionalKeys = SessionKeys.derive(secret: secret, sessionID: newSessionID)
        h2cCounter = 0
        c2hReplayWindow = ReplayWindow()
        highestAppliedCounter = 0
        let rawSecret = secret.key.withUnsafeBytes { Data($0) }
        try? await send(.sessionKey(SessionKeyMessage(
            sessionID: newSessionID,
            secret: B64UData(rawSecret),
            validForMs: ProtocolConstants.sessionKeyValidForMsDefault
        )))
    }

    // MARK: - Motion (spec §3.5)

    private func handleMotionBatchFrame(_ body: Data) async {
        guard let payloads = try? MotionBatch.decode(body) else { return }
        for payload in payloads {
            applyMotion(payload, channel: .tcp, shouldApply: true)
        }
    }

    private func handleIncomingDatagram(_ data: Data) async {
        guard let sessionID, let keys = directionalKeys, data.count == MotionCrypto.datagramLength else { return }
        let bytes = Array(data)
        guard let header = MotionCrypto.peekHeader(datagram: bytes) else { return }
        var window = c2hReplayWindow
        let result = MotionCrypto.openAuthenticated(
            datagram: bytes,
            resolveKey: { candidate in candidate == sessionID ? keys.clientToHost : nil },
            window: &window
        )
        c2hReplayWindow = window
        guard case .success(let plaintext) = result, let payload = MotionPayload(data: Data(plaintext)) else { return }

        if payload.flags.contains(.probe) {
            await reflectProbe(payload)
            return
        }

        // spec §3.5.4: an accepted datagram more than 8 behind the highest *applied* counter is
        // not applied.
        let shouldApply = !ReplayWindow.isStaleToApply(counter: header.counter, highestApplied: highestAppliedCounter)
        if shouldApply {
            highestAppliedCounter = max(highestAppliedCounter, header.counter)
        }
        applyMotion(payload, channel: .udp, shouldApply: shouldApply)
    }

    private func reflectProbe(_ probe: MotionPayload) async {
        guard let sessionID, let keys = directionalKeys, let channel = datagramChannel else { return }
        let echo = MotionPayload(flags: [.echo], source: .probe, samples: 0, timestamp: probe.timestamp)
        var output = [UInt8](repeating: 0, count: MotionCrypto.datagramLength)
        guard (try? MotionCrypto.seal(
            payload: Array(echo.encoded()),
            sessionID: sessionID,
            counter: h2cCounter,
            key: keys.hostToClient,
            into: &output
        )) != nil else { return }
        h2cCounter += 1
        try? channel.send(Data(output))
    }

    private func applyMotion(_ payload: MotionPayload, channel: MotionChannelKind, shouldApply: Bool) {
        let nowUs = nowMicros()
        lastMotion = (clientTs: Int64(payload.timestamp), hostTs: nowUs)
        eventsContinuation.yield(.motion(MotionDeltaEvent(payload: payload, channel: channel, shouldApply: shouldApply)))
    }
}

private enum SecureRandomBytes {
    static func generate(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let result = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard result == errSecSuccess else {
            throw CoreError.internalFailure("SecRandomCopyBytes failed with status \(result)")
        }
        return Data(bytes)
    }
}
