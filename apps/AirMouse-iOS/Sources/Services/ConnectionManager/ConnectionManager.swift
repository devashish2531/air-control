// Services/ConnectionManager/ConnectionManager.swift
// Drives the client-side connection lifecycle end to end: discovery, pairing, trusted reconnect,
// backoff, suspend/resume, heartbeat/probe, error mapping. Wraps `AirMouseCore`'s pure
// `ConnectionStateMachine` (spec §4.5.1) and owns one `ClientSessioning` at a time — the only
// `Network`-importing, actor-crossing coordination point this agent's assignment covers.
//
// Conforms to the shell's `ConnectionManaging` + `PairingRouting` (App/ServiceProtocols.swift) so
// `AppEnvironment.connection`/`.pairingRouter` can be swapped for a live instance of this type
// without editing those files; `PairingScreen`/`DevicesScreen` (this agent's own features) recover
// the richer surface below by downcasting `environment.connection as? ConnectionManager`, since
// this agent owns both ends of that wiring.

import Foundation
import Network
import Observation
import Security
import AirMouseCore
import AirMouseCrypto
import AirMouseFilters
import AirMouseProtocol
import UIKit

/// Progress states `PairingScreen` renders (spec §4.1.2 / §9). Distinct from the shell's
/// `ConnectionState` because pairing has its own "verifying"/"paired" beats mid-handshake that
/// the coarser shell enum doesn't carry.
public enum PairingProgress: Sendable, Equatable {
    case idle
    case connecting(hostName: String?)
    case verifying(hostName: String)
    case paired(hostName: String)
    case failed(AppError)
}

/// One candidate address's outcome from the most recent connect attempt (spec §9 diagnostics
/// deliverable) — `PairingScreen`'s "Details" disclosure lists these, and `ConnectionManager` logs
/// them at `.error` on failure. Never carries secrets/proofs, only the address, a short
/// human-readable outcome, and elapsed time.
public struct AddressAttemptResult: Sendable, Equatable, Identifiable {
    public var id: String { "\(address)#\(outcome)" }
    public let address: String
    public let outcome: String
    public let elapsedMs: Int
    public let succeeded: Bool
    public let isTLSFailure: Bool
    /// The precise transport-level classification for this candidate (`nil` on success). Lets
    /// `mapPairingError`/`mapConnectError` pick the single most diagnostically useful failure among
    /// several candidates instead of collapsing everything to a boolean (spec §9 diagnostics +
    /// the UX-fix deliverable's typed classification).
    public let failure: TransportFailure?

    public init(address: String, outcome: String, elapsedMs: Int, succeeded: Bool, isTLSFailure: Bool, failure: TransportFailure? = nil) {
        self.address = address
        self.outcome = outcome
        self.elapsedMs = elapsedMs
        self.succeeded = succeeded
        self.isTLSFailure = isTLSFailure
        self.failure = failure
    }
}

/// One "Mac known to this device" row for `DevicesScreen`: a trusted record plus its live browse
/// status, if currently visible.
public struct KnownHostRow: Sendable, Identifiable, Equatable {
    public enum Status: Sendable, Equatable {
        case connected
        case available
        case notFound
    }

    public var record: TrustedDeviceRecord
    public var status: Status
    /// The TXT/QR host ID, if known — lets `DevicesScreen` cross-reference `discoveredHosts` live
    /// as browsing continues, without re-running `refreshKnownHostRows()` on every browse tick.
    public var hostID: Data?
    public var id: String { record.id }
}

/// `@unchecked Sendable`: every stored property is only ever touched on `MainActor` (enforced by
/// the class's own `@MainActor` isolation — this conformance only lets a *reference* to the
/// instance cross into other isolation domains, e.g. `Task.detached` in `ConnectionMotionSink`,
/// where every actual member access still requires `await` and hops back to `MainActor`).
@MainActor
@Observable
public final class ConnectionManager: ConnectionManaging, PairingRouting, @unchecked Sendable {
    // MARK: - Shell-facing state (ConnectionManaging)

    public private(set) var connectionState: ConnectionState = .idle
    public var currentHostName: String? {
        switch connectionState {
        case .connected(let name), .reconnecting(let name): return name
        default: return nil
        }
    }

    // MARK: - Pairing/Devices-facing state

    public private(set) var pairingProgress: PairingProgress = .idle
    public private(set) var discoveredHosts: [DiscoveredHost] = []
    public private(set) var browseState: BonjourBrowser.BrowseState = .idle
    public private(set) var knownHostRows: [KnownHostRow] = []
    public private(set) var latestHostState: HostState?
    public private(set) var latestMacroList: MacroList?
    public private(set) var lastError: AppError?
    /// Per-candidate outcome of the most recent connect/pair attempt, newest attempt overwriting
    /// the last — `PairingScreen`'s "Details" disclosure (spec §9 diagnostics deliverable).
    public private(set) var lastConnectionAttempts: [AddressAttemptResult] = []

    public let knownHosts: KnownHostsStore

    /// The live session, for the sink adapters (`ConnectionSinks.swift`) to forward wire calls
    /// onto. `nil` whenever `connectionState` isn't `.connected`.
    public var activeSession: (any ClientSessioning)? { session }

    private var pendingMacroInvokes: [UUID: CheckedContinuation<MacroResult, Never>] = [:]

    // MARK: - Internals

    private var coreState: AirMouseCore.ConnectionState = .idle
    private var session: (any ClientSessioning)?
    private var currentFingerprint: Fingerprint?
    private var currentDisplayName: String?
    private var currentResolvedHost: String?

    private var eventsTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var browseTask: Task<Void, Never>?
    private var browseStateTask: Task<Void, Never>?
    private var settingsObservationStarted = false

    /// spec §4.5.5 fast-resume: `willResignActive` schedules a suspend under this task rather than
    /// tearing the session down immediately; `didBecomeActive` cancels it if it fires first. Tagged
    /// with `suspendGeneration` so a stale, already-scheduled suspend can never land after a newer
    /// scene-phase transition has moved on (see `handleScenePhaseInactive`).
    private var pendingSuspendTask: Task<Void, Never>?
    private var suspendGeneration = 0
    /// How long `.inactive`/`.background` must persist before the session is actually torn down. A
    /// Control Center swipe or notification banner resolves well inside this window.
    private static let suspendDebounceNanoseconds: UInt64 = 1_000_000_000

    #if DEBUG
    /// Test-only network substitute (Tests/ConnectionManagerTests.swift): when set,
    /// `connectToKnownHost` hands off to this closure instead of dialing a real `NWConnection`.
    /// Returning `nil` simulates every candidate failing. Always `nil` outside tests.
    var testConnectHook: ((TrustedDeviceRecord) async -> (any ClientSessioning, String)?)?
    #endif

    private var backoff = Backoff()
    private var reconnectBeganAt: TimeInterval?

    private let bonjourBrowser = BonjourBrowser()
    private let clock: any Clock
    private let clientIdentity: SecIdentity
    private let clientFingerprint: Fingerprint
    private let device: Hello.Device
    private let userSettings: UserSettings
    private let diagnostics: DiagnosticsModel
    private let idleTimer: IdleTimer
    private let haptics: any HapticsService

    public init(
        knownHosts: KnownHostsStore,
        userSettings: UserSettings,
        diagnostics: DiagnosticsModel,
        idleTimer: IdleTimer,
        haptics: any HapticsService,
        clock: any Clock = SystemClock(),
        clientIdentity: GeneratedIdentity
    ) {
        self.knownHosts = knownHosts
        self.userSettings = userSettings
        self.diagnostics = diagnostics
        self.idleTimer = idleTimer
        self.haptics = haptics
        self.clock = clock
        self.clientIdentity = clientIdentity.secIdentity
        self.clientFingerprint = clientIdentity.fingerprint
        self.device = Hello.Device(
            name: UIDevice.current.name,
            model: Self.hardwareModelIdentifier(),
            os: "iOS \(UIDevice.current.systemVersion)",
            app: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        )
        observeAppLifecycle()
        observeSettingsChanges()
        Task { await self.refreshKnownHostRows() }
    }

    // MARK: - ConnectionManaging

    /// spec §4.5.5: "if a trusted target exists and auto-connect is on → Connecting immediately."
    /// Also the shell's generic "(re)connect" entry point (e.g. a future manual retry button).
    public func connect() async {
        guard session == nil else { return }
        guard let hex = knownHosts.lastUsedHostFingerprintHex,
              let fingerprint = Fingerprint(hexString: hex),
              let record = await knownHosts.lookup(fingerprint: fingerprint), !record.revoked
        else {
            return
        }
        await connectToKnownHost(record)
    }

    public func disconnect() async {
        reconnectTask?.cancel()
        reconnectTask = nil
        if let session {
            try? await session.sendGoodbye(.userQuit)
            await session.close(reason: .userQuit)
        }
        await teardownSession(nextState: .idle)
    }

    // MARK: - PairingRouting

    public func routePairing(url: URL) {
        Task { await pair(urlString: url.absoluteString) }
    }

    // MARK: - Pairing (spec §3.2, §4.1.2)

    /// Parses `urlString` (QR scan or pasted link) and drives the full pairing handshake.
    public func pair(urlString: String) async {
        do {
            let url = try PairingClient.parse(urlString)
            await pair(url: url)
        } catch {
            pairingProgress = .failed(.pairingURLInvalid)
        }
    }

    /// Lets `PairingScreen`'s "Try again" clear a `.failed` overlay back to `.idle` without
    /// re-driving any connection state (the failed attempt already tore itself down).
    public func resetPairingProgress() {
        pairingProgress = .idle
    }

    public func pair(url: PairingURL) async {
        guard let fingerprint = Fingerprint(bytes: Array(url.fingerprint)) else {
            pairingProgress = .failed(.pairingFingerprintMismatch)
            return
        }
        await disconnectCurrentSessionQuietly()
        coreState = .pairing
        connectionState = .pairing
        pairingProgress = .connecting(hostName: url.hostName)

        let candidates = url.addresses.filter(Self.isUsableCandidateAddress).map {
            AddressSelector.Candidate(address: $0, port: url.tcpPort, source: .qr)
        }
        do {
            let channel = try await withOverallTimeout(Double(ProtocolConstants.addressOverallConnectTimeoutMs) / 1000.0) {
                try await self.connectControlChannel(liveEndpoint: nil, candidates: candidates, fingerprint: fingerprint)
            }
            let newSession = makeSession(control: channel, resolvedHost: channel.resolvedHost)
            eventsTask?.cancel()
            eventsTask = Task { [weak self] in await self?.consumeEvents(of: newSession) }
            pairingProgress = .verifying(hostName: url.hostName)
            let info = try await newSession.pair(url: url, macroRevision: nil)
            session = newSession
            currentFingerprint = fingerprint
            currentDisplayName = info.host.name
            currentResolvedHost = channel.resolvedHost
            backoff.reset()

            // spec item 4: a host id already trusted under a *different* fingerprint (the Mac's
            // identity was regenerated, e.g. a factory-reset helper) must be replaced, not left
            // sitting alongside the freshly-paired record for the same physical Mac.
            await Self.replaceStaleRecord(forHostID: url.hostID, newFingerprint: fingerprint, knownHosts: knownHosts)

            let record = TrustedDeviceRecord(
                fingerprint: fingerprint,
                name: info.host.name,
                model: info.host.model,
                osVersion: info.host.os,
                firstPaired: Date(),
                lastSeen: Date()
            )
            await knownHosts.add(record)
            await knownHosts.setConnectionInfo(
                KnownHostConnectionInfo(
                    tcpPort: url.tcpPort,
                    udpPort: info.udpPort,
                    qrAddresses: url.addresses,
                    hostID: url.hostID
                ),
                fingerprint: fingerprint
            )
            if let resolved = channel.resolvedHost {
                await knownHosts.recordSuccessfulConnection(fingerprint: fingerprint, address: resolved)
            }
            knownHosts.setLastUsedHost(fingerprint: fingerprint)
            userSettings.lastHostID = fingerprint.hexString

            coreState = .connected
            connectionState = .connected(hostName: info.host.name)
            pairingProgress = .paired(hostName: info.host.name)
            haptics.fire(.pairingSuccess)
            idleTimer.acquire("connected")
            startTickers()
            await refreshKnownHostRows()
        } catch {
            haptics.fire(.pairingFailure)
            let appError = Self.mapPairingError(error, attempts: lastConnectionAttempts, hostName: Self.displayHostName(url.hostName))
            pairingProgress = .failed(appError)
            lastError = appError
            coreState = .failed(.pairingFailed)
            connectionState = .failed(reason: appError.presentation.message)
            eventsTask?.cancel()
            Self.logConnectFailure(context: "pair", appError: appError, attempts: lastConnectionAttempts)
        }
    }

    // MARK: - Devices (spec §4.1.3)

    public func startBrowsing() {
        guard browseTask == nil else { return }
        bonjourBrowser.start()
        // Two independent plain `Task`s (not `async let`/`addTask`, which are `@Sendable` and lose
        // this @MainActor class's isolation) so each loop can mutate `discoveredHosts`/
        // `browseState` directly.
        browseTask = Task { [weak self] in
            guard let self else { return }
            for await hosts in self.bonjourBrowser.hosts {
                guard !Task.isCancelled else { return }
                self.discoveredHosts = hosts
                await self.maybeAutoConnect(hosts: hosts)
            }
        }
        browseStateTask = Task { [weak self] in
            guard let self else { return }
            for await state in self.bonjourBrowser.state {
                guard !Task.isCancelled else { return }
                self.browseState = state
            }
        }
    }

    public func stopBrowsing() {
        browseTask?.cancel()
        browseTask = nil
        browseStateTask?.cancel()
        browseStateTask = nil
        bonjourBrowser.stop()
        discoveredHosts = []
    }

    public func connectToKnownHost(_ record: TrustedDeviceRecord) async {
        guard session == nil else { return }
        #if DEBUG
        // Test-only seam (Tests/ConnectionManagerTests.swift): lets a suspend→resume test drive
        // this method's real state transitions with a mock `ClientSessioning` instead of a real
        // `NWConnection`, so the fix above can be verified reconnecting all the way to `.connected`
        // without real networking. Always `nil` outside tests.
        if let hook = testConnectHook {
            await disconnectCurrentSessionQuietly()
            coreState = .connecting
            connectionState = .connecting
            if let (newSession, hostName) = await hook(record) {
                session = newSession
                currentFingerprint = record.fingerprint
                currentDisplayName = hostName
                backoff.reset()
                coreState = .connected
                connectionState = .connected(hostName: hostName)
                idleTimer.acquire("connected")
                startTickers()
                await refreshKnownHostRows()
            } else {
                coreState = .failed(.allCandidatesFailed)
                connectionState = .failed(reason: "test hook returned nil")
            }
            return
        }
        #endif
        await disconnectCurrentSessionQuietly()
        coreState = .connecting
        connectionState = .connecting

        let info = await knownHosts.connectionInfo(fingerprint: record.fingerprint)

        func hostIDMatches(_ discovered: DiscoveredHost) -> Bool {
            guard let hostID = info?.hostID else { return false }
            return discovered.id == hostID
        }
        let live = discoveredHosts.first(where: hostIDMatches)

        let lastKnown = (info?.lastKnownAddresses ?? []).map(\.address).filter(Self.isUsableCandidateAddress).map {
            AddressSelector.Candidate(address: $0, port: info?.tcpPort ?? ProtocolConstants.defaultTCPPort, source: .lastKnown)
        }
        let qr = (info?.qrAddresses ?? []).filter(Self.isUsableCandidateAddress).map {
            AddressSelector.Candidate(address: $0, port: info?.tcpPort ?? ProtocolConstants.defaultTCPPort, source: .qr)
        }

        do {
            let channel = try await withOverallTimeout(Double(ProtocolConstants.addressOverallConnectTimeoutMs) / 1000.0) {
                try await self.connectControlChannel(liveEndpoint: live?.endpoint, candidates: lastKnown + qr, fingerprint: record.fingerprint)
            }
            let newSession = makeSession(control: channel, resolvedHost: channel.resolvedHost)
            eventsTask?.cancel()
            eventsTask = Task { [weak self] in await self?.consumeEvents(of: newSession) }
            let ack = try await newSession.connect(macroRevision: latestMacroList?.revision)
            session = newSession
            currentFingerprint = record.fingerprint
            currentDisplayName = ack.host.name
            currentResolvedHost = channel.resolvedHost
            backoff.reset()

            if let resolved = channel.resolvedHost {
                await knownHosts.recordSuccessfulConnection(fingerprint: record.fingerprint, address: resolved)
            }
            await knownHosts.updateLastSeen(fingerprint: record.fingerprint, date: Date())
            knownHosts.setLastUsedHost(fingerprint: record.fingerprint)
            userSettings.lastHostID = record.fingerprint.hexString

            coreState = .connected
            connectionState = .connected(hostName: ack.host.name)
            idleTimer.acquire("connected")
            startTickers()
            try? await newSession.sendSettings(Self.wireSettings(from: userSettings.snapshot))
            await refreshKnownHostRows()
        } catch {
            let appError = Self.mapConnectError(error, hostName: record.displayName, attempts: lastConnectionAttempts)
            lastError = appError
            coreState = .failed(.allCandidatesFailed)
            connectionState = .failed(reason: appError.presentation.message)
            eventsTask?.cancel()
            Self.logConnectFailure(context: "connectToKnownHost", appError: appError, attempts: lastConnectionAttempts)
        }
    }

    /// spec §4.1.3 "Forget": deletes Keychain cert + record + (macro cache is the Macros
    /// feature's own responsibility on the same fingerprint).
    public func forget(_ record: TrustedDeviceRecord) async {
        if currentFingerprint == record.fingerprint {
            await disconnect()
        }
        await knownHosts.remove(fingerprint: record.fingerprint)
        if knownHosts.lastUsedHostFingerprintHex == record.fingerprint.hexString {
            knownHosts.setLastUsedHost(fingerprint: nil)
        }
        await refreshKnownHostRows()
    }

    public func refreshKnownHostRows() async {
        let records = await knownHosts.list().filter { !$0.revoked }
        var rows: [KnownHostRow] = []
        for record in records {
            let status: KnownHostRow.Status
            if currentFingerprint == record.fingerprint, case .connected = connectionState {
                status = .connected
            } else {
                status = .notFound // liveness refined by `DevicesScreen` against `discoveredHosts`.
            }
            let hostID = await knownHosts.connectionInfo(fingerprint: record.fingerprint)?.hostID
            rows.append(KnownHostRow(record: record, status: status, hostID: hostID))
        }
        knownHostRows = rows
    }

    // MARK: - Macro invocation (spec §5.5.5) — `RemoteCommandSink.invokeMacro`'s implementation

    /// Sends `macroInvoke` then awaits the matching `macroResult` by macro `id` (not envelope
    /// `ref`, which `ClientSession.invokeMacro` does not surface to callers). Times out after
    /// `ProtocolConstants.macroScriptTimeoutSeconds` — the longest of the spec's per-kind macro
    /// timeouts — so a lost/never-sent result can't hang the caller forever.
    public func invokeMacroAwaitingResult(id: UUID, confirmed: Bool, session: any ClientSessioning) async throws -> MacroInvokeOutcome {
        try await session.invokeMacro(id: id, confirmed: confirmed)
        do {
            let result = try await withOverallTimeout(Double(ProtocolConstants.macroScriptTimeoutSeconds)) {
                await self.awaitMacroResult(id: id)
            }
            return MacroInvokeOutcome(code: result.code, message: result.message)
        } catch {
            pendingMacroInvokes.removeValue(forKey: id)
            return MacroInvokeOutcome(code: .timeout, message: "")
        }
    }

    private func awaitMacroResult(id: UUID) async -> MacroResult {
        await withCheckedContinuation { continuation in
            pendingMacroInvokes[id] = continuation
        }
    }

    // MARK: - Session plumbing

    private func makeSession(control: NWControlChannel, resolvedHost: String?) -> any ClientSessioning {
        let provider: DatagramChannelProvider = { udpPort in
            let host = resolvedHost ?? ""
            return try await NWDatagramChannel.connect(host: host, udpPort: udpPort)
        }
        return ClientSession(
            control: control,
            datagramProvider: provider,
            clock: clock,
            localFingerprint: clientFingerprint,
            device: device
        )
    }

    /// One candidate's raw outcome from the task group below, before it's folded into the
    /// published `AddressAttemptResult` (kept internal/untyped here since `NWControlChannel` isn't
    /// `Equatable` and doesn't need to be — only the public summary type does).
    private struct CandidateAttempt: Sendable {
        let address: String
        let elapsedMs: Int
        let result: Result<NWControlChannel, Error>
    }

    private func connectControlChannel(
        liveEndpoint: NWEndpoint?,
        candidates: [AddressSelector.Candidate],
        fingerprint: Fingerprint
    ) async throws -> NWControlChannel {
        let ordered = AddressSelector.order(bonjour: nil, lastKnown: candidates.filter { $0.source == .lastKnown }, qr: candidates.filter { $0.source == .qr })
        var attemptCount = ordered.count + (liveEndpoint != nil ? 1 : 0)
        guard attemptCount > 0 else { throw TransportFailure.unreachable }

        // `SecIdentity` is a CF type with no `Sendable` conformance; box it (matching
        // `GeneratedIdentity`'s own `@unchecked Sendable` rationale: Security.framework's CF
        // handles are safe to hand across isolation domains as opaque, effectively-immutable
        // values) so it can cross into these `@Sendable` `addTask` closures.
        let identity = SendableSecIdentity(clientIdentity)
        lastConnectionAttempts = [] // fresh per attempt — see `PairingScreen`'s "Details" disclosure.

        return try await withThrowingTaskGroup(of: CandidateAttempt.self) { group in
            var index = 0
            if let liveEndpoint {
                group.addTask {
                    let start = Date()
                    do {
                        let channel = try await NWControlChannel.connect(to: liveEndpoint, clientIdentity: identity.value, expectedHostFingerprint: fingerprint)
                        return CandidateAttempt(address: "bonjour", elapsedMs: Self.elapsedMs(since: start), result: .success(channel))
                    } catch {
                        return CandidateAttempt(address: "bonjour", elapsedMs: Self.elapsedMs(since: start), result: .failure(error))
                    }
                }
                index += 1
            }
            for candidate in ordered {
                let staggerIndex = index
                group.addTask {
                    let start = Date()
                    do {
                        if staggerIndex > 0 {
                            try await Task.sleep(nanoseconds: UInt64(staggerIndex) * UInt64(ProtocolConstants.addressConnectStaggerMs) * 1_000_000)
                        }
                        try Task.checkCancellation()
                        let channel = try await NWControlChannel.connect(
                            host: candidate.address,
                            port: candidate.port,
                            clientIdentity: identity.value,
                            expectedHostFingerprint: fingerprint
                        )
                        return CandidateAttempt(address: candidate.address, elapsedMs: Self.elapsedMs(since: start), result: .success(channel))
                    } catch {
                        return CandidateAttempt(address: candidate.address, elapsedMs: Self.elapsedMs(since: start), result: .failure(error))
                    }
                }
                index += 1
            }
            attemptCount = index

            var lastError: Error = TransportFailure.unreachable
            var remaining = attemptCount
            var winner: NWControlChannel?
            // Collected progressively (not just at the end) so a candidate that finishes before
            // the outer `withOverallTimeout` cancels the rest still shows up in diagnostics.
            while remaining > 0, let attempt = try await group.next() {
                remaining -= 1
                let outcome: String
                let succeeded: Bool
                let isTLS: Bool
                let classified: TransportFailure?
                switch attempt.result {
                case .success(let channel):
                    outcome = "connected"
                    succeeded = true
                    isTLS = false
                    classified = nil
                    winner = channel
                case .failure(let error):
                    outcome = Self.describeOutcome(error)
                    succeeded = false
                    isTLS = Self.isTLSFailure(error)
                    classified = error as? TransportFailure
                    lastError = error
                }
                lastConnectionAttempts.append(AddressAttemptResult(
                    address: attempt.address, outcome: outcome, elapsedMs: attempt.elapsedMs,
                    succeeded: succeeded, isTLSFailure: isTLS, failure: classified
                ))
                if winner != nil { break }
            }
            group.cancelAll()
            if let winner { return winner }
            throw lastError
        }
    }

    nonisolated private static func elapsedMs(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    nonisolated private static func isTLSFailure(_ error: Error) -> Bool {
        switch error as? TransportFailure {
        case .tlsAlertFromPeer, .peerCertificateMismatch, .clientIdentityFailure: return true
        default: return false
        }
    }

    /// Human-readable outcome for one candidate — no secrets/proofs, just what happened (spec §9
    /// diagnostics deliverable: "per-address outcome (refused/timeout/TLS error text/`NWError`
    /// description)") — and the real text `PairingScreen`'s "Details" disclosure shows.
    nonisolated private static func describeOutcome(_ error: Error) -> String {
        switch error as? TransportFailure {
        case .unreachable: return "unreachable"
        case .localNetworkDenied: return "local network access denied"
        case .tlsAlertFromPeer(let description): return description
        case .peerCertificateMismatch(let expected, let actual): return "certificate mismatch (expected \(expected)…, got \(actual)…)"
        case .clientIdentityFailure(let description): return description
        case .closedBeforeReady: return "connection closed before ready"
        case .timedOut: return "timed out"
        case .invalidPort(let port): return "invalid port \(port)"
        case nil: return String(describing: error)
        }
    }

    /// The most diagnostically useful `TransportFailure` among everything one attempt saw: a
    /// specific TLS-classification candidate always outranks a generic terminal `.unreachable`/
    /// `.timedOut` — several candidates can fail for boring reasons (nothing listening on that
    /// address) while just one hit the interesting failure that actually explains what happened.
    nonisolated private static func mostSpecificFailure(_ terminal: TransportFailure, attempts: [AddressAttemptResult]) -> TransportFailure {
        func rank(_ failure: TransportFailure) -> Int {
            switch failure {
            case .peerCertificateMismatch: return 4
            case .tlsAlertFromPeer: return 3
            case .clientIdentityFailure: return 3
            case .localNetworkDenied: return 2
            case .closedBeforeReady, .timedOut: return 1
            case .unreachable, .invalidPort: return 0
            }
        }
        let candidates = attempts.compactMap(\.failure) + [terminal]
        return candidates.max(by: { rank($0) < rank($1) }) ?? terminal
    }

    /// spec §9 diagnostics deliverable: drop zone-stripped IPv6 link-local literals (`fe80::…`
    /// with no `%zone`) before they ever reach `AddressSelector` — `AirMouseProtocol.IPLiteral`'s
    /// own grammar forbids a zone id ("no brackets, no zone"), so every QR/`lastKnownAddresses`
    /// literal in that range is one `Network.framework` cannot route to from this device; wasting
    /// a stagger/timeout slot on it only delays reaching an address that would actually work.
    nonisolated static func isUsableCandidateAddress(_ address: String) -> Bool {
        let lowered = address.lowercased()
        let isLinkLocalIPv6 = lowered.hasPrefix("fe8") || lowered.hasPrefix("fe9") || lowered.hasPrefix("fea") || lowered.hasPrefix("feb")
        return !isLinkLocalIPv6 || lowered.contains("%")
    }

    private func withOverallTimeout<T: Sendable>(_ seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TransportFailure.timedOut
            }
            guard let result = try await group.next() else {
                throw TransportFailure.timedOut
            }
            group.cancelAll()
            return result
        }
    }

    private func consumeEvents(of session: any ClientSessioning) async {
        for await event in session.events {
            guard !Task.isCancelled else { return }
            handle(event: event)
        }
    }

    private func handle(event: ClientEvent) {
        switch event {
        case .pairingChallengeReceived(let hostName):
            pairingProgress = .verifying(hostName: hostName)
        case .paired:
            break // trust persisted by the caller once `pair(url:)` returns.
        case .connected:
            break // handled by the caller's own return value.
        case .hostState(let hostState):
            latestHostState = hostState
        case .macroList(let macroList):
            latestMacroList = macroList
        case .macroResult(let result):
            if let continuation = pendingMacroInvokes.removeValue(forKey: result.id) {
                continuation.resume(returning: result)
            }
        case .error(let payload):
            let appError = Self.mapErrorPayload(payload)
            lastError = appError
            if payload.fatal {
                Task { await self.handleConnectionLoss(reason: appError.presentation.message) }
            }
        case .goodbye(let reason):
            Task { await self.handleConnectionLoss(reason: "goodbye: \(reason.rawValue)") }
        case .fallbackEngaged, .fallbackRecovered:
            break // reflected in `SessionStats.isFallbackEngaged` on the next tick.
        case .stats(let stats):
            ingestStats(stats)
        case .disconnected(let reason):
            Task { await self.handleConnectionLoss(reason: reason) }
        }
    }

    /// `ConnectionMotionSink.sendMotion(_:)` forwards every swallowed `sendMotion`/`sendProbe`
    /// failure here instead of dropping it via a bare `try?` — see `DiagnosticsModel.
    /// motionSendFailureCounts`'s doc comment for why that visibility matters.
    public func recordMotionSendFailure(kind: String) {
        diagnostics.recordMotionSendFailure(kind: kind)
    }

    private func ingestStats(_ stats: SessionStats) {
        diagnostics.ingest(LatencySample(
            timestamp: Date(),
            rttMillisP50: stats.rttP50.map { $0 * 1000 },
            rttMillisP95: stats.rttP95.map { $0 * 1000 },
            probeRTTMillis: nil,
            oneWayEstimateMillis: stats.oneWayMotionLatency.map { $0 * 1000 },
            lossPercent: stats.lossPercent,
            channel: stats.isFallbackEngaged ? .tcpFallback : .udp,
            inFlightDatagrams: 0
        ))
    }

    /// Connected → Reconnecting (spec §4.5.1: "no pong 2 s / connection failed / path changed").
    private func handleConnectionLoss(reason: String) async {
        guard session != nil else { return }
        await teardownSession(nextState: nil)
        guard case .connected = coreState else {
            coreState = .failed(.allCandidatesFailed)
            connectionState = .failed(reason: reason)
            return
        }
        coreState = .reconnecting
        if let name = currentDisplayName {
            connectionState = .reconnecting(hostName: name)
        }
        beginReconnectLoop()
    }

    private func beginReconnectLoop() {
        reconnectTask?.cancel()
        reconnectBeganAt = clock.now()
        backoff.reset()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let fingerprint = self.currentFingerprint,
                      let record = await self.knownHosts.lookup(fingerprint: fingerprint), !record.revoked
                else { return }
                if let began = self.reconnectBeganAt, Backoff.hasGivenUp(elapsedSinceReconnectingBegan: self.clock.now() - began) {
                    self.coreState = .failed(.reconnectGiveUpElapsed)
                    self.connectionState = .failed(reason: String(localized: "Couldn't reconnect"))
                    return
                }
                let delay = self.backoff.nextDelay(unitJitter: Double.random(in: -1...1))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled, self.session == nil else { return }
                await self.connectToKnownHost(record)
                if self.session != nil { return } // success — `connectToKnownHost` updated state.
            }
        }
    }

    private func startTickers() {
        tickerTask?.cancel()
        tickerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let session = self.session else { return }
                try? await session.sendHeartbeat()
                try? await session.sendProbe()
                _ = await session.expireOutstandingProbeIfNeeded()
                let stats = await session.currentStats()
                self.ingestStats(stats)
                let mode = await session.expireOutstandingProbeIfNeeded()
                let intervalMs = mode == .fallback ? 1000 : ProtocolConstants.probeIntervalMs
                try? await Task.sleep(nanoseconds: UInt64(intervalMs) * 1_000_000)
            }
        }
    }

    private func teardownSession(nextState: ConnectionState?) async {
        tickerTask?.cancel()
        tickerTask = nil
        eventsTask?.cancel()
        eventsTask = nil
        session = nil
        idleTimer.release("connected")
        if let nextState {
            coreState = .idle
            connectionState = nextState
            currentFingerprint = nil
            currentDisplayName = nil
            currentResolvedHost = nil
        }
        await refreshKnownHostRows()
    }

    private func disconnectCurrentSessionQuietly() async {
        guard let session else { return }
        await session.close(reason: .replaced)
        await teardownSession(nextState: nil)
    }

    private func maybeAutoConnect(hosts: [DiscoveredHost]) async {
        guard session == nil, reconnectTask == nil, userSettings.autoConnectLastHost,
              let hex = knownHosts.lastUsedHostFingerprintHex,
              let fingerprint = Fingerprint(hexString: hex),
              let record = await knownHosts.lookup(fingerprint: fingerprint), !record.revoked,
              let info = await knownHosts.connectionInfo(fingerprint: fingerprint),
              let hostID = info.hostID,
              hosts.contains(where: { $0.id == hostID })
        else { return }
        await connectToKnownHost(record)
    }

    #if DEBUG
    // MARK: - Test-only seams (Tests/ConnectionManagerTests.swift)

    /// Installs `session` as if a connect/reconnect had just succeeded, without driving a real
    /// TLS/UDP handshake, so app-lifecycle suspend/resume (spec §4.5.5) can be exercised
    /// deterministically. Never compiled into a release build.
    func installConnectedSessionForTesting(_ session: any ClientSessioning, hostName: String = "Test Mac") {
        self.session = session
        coreState = .connected
        connectionState = .connected(hostName: hostName)
        currentDisplayName = hostName
    }

    /// Drives `handleScenePhaseInactive`/`handleScenePhaseActive` directly rather than through
    /// `NotificationCenter` — every live `ConnectionManager` observes the *global*
    /// `UIApplication` lifecycle notifications (`object: nil`), so posting them from a test would
    /// also reach any other manager instance alive concurrently elsewhere in the test process.
    func triggerScenePhaseInactiveForTesting() { handleScenePhaseInactive() }
    func triggerScenePhaseActiveForTesting() async { await handleScenePhaseActive() }
    #endif

    // MARK: - App lifecycle (spec §4.5.5)

    private func observeAppLifecycle() {
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleScenePhaseInactive() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.handleScenePhaseActive() }
        }
    }

    /// spec §4.5.5 + fast-resume ("a quick inactive→active flip... must not tear the session down
    /// at all if it lasts under ~1-2 s"): `willResignActive` no longer suspends synchronously.
    /// Instead it schedules a debounced suspend tagged with `suspendGeneration`; if
    /// `handleScenePhaseActive` follows inside the debounce window it cancels this task and the
    /// session is never touched — `coreState`/`connectionState` stay `.connected` throughout.
    ///
    /// This also closes the original race (spec deliverable): the old code set `coreState =
    /// .suspended` synchronously here but only assigned `connectionState = .suspended` inside a
    /// detached `Task` (`teardownSession`). A fast `didBecomeActive` would see the synchronous
    /// `coreState` flip, call `connect()`, and then have that stale `Task` land afterwards and
    /// clobber the fresh connecting/connected state back to `.suspended`. Now the *only* place that
    /// assigns `.suspended` is `performSuspend`, which runs both assignments synchronously in the
    /// same hop as tearing down `session`/timers — so `handleScenePhaseActive`'s `coreState ==
    /// .suspended` check and `connect()`'s `session == nil` check always agree.
    private func handleScenePhaseInactive() {
        guard case .connected = coreState else { return }
        suspendGeneration += 1
        let generation = suspendGeneration
        pendingSuspendTask?.cancel()
        pendingSuspendTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.suspendDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            self?.performSuspend(generation: generation)
        }
    }

    /// The actual suspend, run only after `willResignActive` has persisted past the debounce.
    /// Cancels the reconnect loop and tickers, drops `session`, and flips `coreState`/
    /// `connectionState` to `.suspended` — all synchronously, no `await` in between — then fires
    /// the goodbye/close network I/O off separately since it never needs to observe or mutate
    /// state itself.
    private func performSuspend(generation: Int) {
        guard generation == suspendGeneration, case .connected = coreState else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        tickerTask?.cancel()
        tickerTask = nil
        eventsTask?.cancel()
        eventsTask = nil
        let sessionToClose = session
        session = nil
        idleTimer.release("connected")
        currentFingerprint = nil
        currentDisplayName = nil
        currentResolvedHost = nil
        coreState = .suspended
        connectionState = .suspended
        Task {
            try? await sessionToClose?.sendGoodbye(.background)
            await sessionToClose?.close(reason: .background)
        }
        Task { await self.refreshKnownHostRows() }
    }

    private func handleScenePhaseActive() async {
        pendingSuspendTask?.cancel()
        pendingSuspendTask = nil
        suspendGeneration += 1
        guard case .suspended = coreState else { return }
        await connect()
    }

    // MARK: - Settings (spec §3.4.5 `settings`, on any change)

    private func observeSettingsChanges() {
        withObservationTracking {
            _ = userSettings.snapshot
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if let session = self.session {
                    try? await session.sendSettings(Self.wireSettings(from: self.userSettings.snapshot))
                }
                self.observeSettingsChanges()
            }
        }
    }

    private static func wireSettings(from snapshot: SettingsSnapshot) -> Settings {
        Settings(
            sensitivity: snapshot.pointer.sensitivity,
            acceleration: .default,
            scrollSpeed: snapshot.gestures.scrollSpeed,
            scrollDirection: snapshot.gestures.naturalScroll == .natural ? .natural : (snapshot.gestures.naturalScroll == .inverted ? .inverted : .host),
            momentum: snapshot.gestures.momentum,
            doubleClickIntervalMs: Settings.defaults.doubleClickIntervalMs,
            pinchMode: Settings.defaults.pinchMode,
            textRateCharsPerSec: Settings.defaults.textRateCharsPerSec
        )
    }

    // MARK: - Error mapping (spec §9)

    /// - Parameters:
    ///   - attempts: this attempt's per-candidate outcomes (`lastConnectionAttempts`, read at the
    ///     catch site before anything else resets it) — used to tell "never reached a TLS peer at
    ///     all" (every candidate refused/timed out) apart from "reached one, but its fingerprint
    ///     didn't match" (spec §9 diagnostics deliverable, (a) vs (b)).
    nonisolated static func mapPairingError(_ error: Error, attempts: [AddressAttemptResult], hostName: String) -> AppError {
        if let transportFailure = error as? TransportFailure {
            let anySucceeded = attempts.contains { $0.succeeded }
            switch mostSpecificFailure(transportFailure, attempts: attempts) {
            case .localNetworkDenied: return .localNetworkDenied
            case .peerCertificateMismatch:
                // A pin mismatch *during pairing* only ever means the peer that answered isn't the
                // one that showed this QR (spec §9 E-PAIR-FP has the exact copy for that already) —
                // never `.hostIdentityChanged`, which is the reconnect-to-a-trusted-host wording.
                return .pairingFingerprintMismatch
            case .tlsAlertFromPeer:
                // The Mac's own verify block rejected us mid-pairing (e.g. the pairing window
                // closed the instant before our handshake landed).
                return .hostRefusedUntrusted
            case .clientIdentityFailure(let description):
                return .tlsHandshakeFailed(detail: description)
            case .timedOut:
                if anySucceeded { return .pairingExpired } // TCP/TLS fine; the pairChallenge itself never arrived (spec §3.2.6).
                if attempts.isEmpty { return .pairingExpired } // no candidate ever reported in — same inference as before.
                return .hostUnreachable(hostName: hostName)
            case .unreachable, .closedBeforeReady, .invalidPort:
                return attempts.isEmpty ? .connectionFailed(hostName: hostName) : .hostUnreachable(hostName: hostName)
            }
        }
        if let core = error as? CoreError {
            switch core {
            case .pairingExpired: return .pairingExpired
            case .pairingInvalidProof: return .pairingWrongCode // spec §9 diagnostics deliverable (d): distinct from an expired secret.
            case .pairingTooManyDevices: return .pairingDeviceLimit
            case .pairingHostProofInvalid: return .pairingHostProofInvalid
            case .pairingAlreadyTrusted: return .pairingAlreadyTrusted
            case .authUntrusted: return .authUntrusted
            case .authRevoked: return .authRevoked
            case .versionMismatch: return .versionAppOutdated
            case .rateLimited: return .pairingRateLimited
            case .protocolMismatch(let expected, let got):
                return .protocolMismatch(detail: "expected \(expected), got \(got)")
            // A hang mid-pairing (the host silently answered something the client wasn't waiting
            // for, then never followed up) used to surface here as `.generic(code: "internal")` —
            // see this file's report for the exact reproduction. `.channelClosed` specifically is
            // reachable that way, so it gets the same readable copy as any other "never got
            // through" outcome instead of the bare wire-code fallback below.
            case .channelClosed: return .connectionFailed(hostName: hostName)
            default: return .generic(code: core.wireCode?.rawValue ?? "internal")
            }
        }
        return .pairingHostProofInvalid
    }

    /// See `mapPairingError`'s doc comment for the same "pick the most specific candidate" logic,
    /// but for a reconnect to an already-trusted host — three distinct copy-worthy outcomes instead
    /// of one shared `.tlsVerificationFailed`: the Mac refusing us (`.hostRefusedUntrusted`), our
    /// own pin rejecting the Mac's regenerated identity (`.hostIdentityChanged`), and our own client
    /// identity failing to sign (`.tlsHandshakeFailed`). `hostUnreachable` is reserved for true
    /// TCP-level failures (`.unreachable`/`.closedBeforeReady`/our own watchdog `.timedOut`) — never
    /// for a TLS-level rejection, which used to collapse into the same "Couldn't reach" copy.
    nonisolated static func mapConnectError(_ error: Error, hostName: String, attempts: [AddressAttemptResult]) -> AppError {
        guard let transportFailure = error as? TransportFailure else { return .connectionFailed(hostName: hostName) }
        switch mostSpecificFailure(transportFailure, attempts: attempts) {
        case .localNetworkDenied: return .localNetworkDenied
        case .peerCertificateMismatch:
            // Reconnect to an already-trusted Mac whose certificate no longer matches what's
            // pinned — spec item 2's "This Mac's identity has changed" wording.
            return .hostIdentityChanged
        case .tlsAlertFromPeer:
            // The Mac's own verify block rejected us — most often its pairing window is closed and
            // it no longer recognizes this client certificate as trusted.
            return .hostRefusedUntrusted
        case .clientIdentityFailure(let description):
            return .tlsHandshakeFailed(detail: description)
        case .timedOut, .unreachable, .closedBeforeReady, .invalidPort:
            return attempts.isEmpty ? .connectionFailed(hostName: hostName) : .hostUnreachable(hostName: hostName)
        }
    }

    /// spec item 4: pairing a URL whose host id already has a trust record with a *different*
    /// fingerprint (the Mac's identity was regenerated) replaces that stale record instead of
    /// leaving two entries for the same physical Mac. `static`/standalone so it's testable with a
    /// real `KnownHostsStore` and no live `NWConnection` (see `ConnectionManagerTests`).
    nonisolated static func replaceStaleRecord(forHostID hostID: Data, newFingerprint: Fingerprint, knownHosts: KnownHostsStore) async {
        for record in await knownHosts.list() where record.fingerprint != newFingerprint {
            guard await knownHosts.connectionInfo(fingerprint: record.fingerprint)?.hostID == hostID else { continue }
            await knownHosts.remove(fingerprint: record.fingerprint)
        }
    }

    /// Non-empty, human-friendly host name for interpolation into `.hostUnreachable`'s copy — the
    /// QR's `hostName` field is optional (spec §3.1.3), and an empty "Couldn't reach ." reads badly.
    nonisolated static func displayHostName(_ hostName: String?) -> String {
        guard let hostName, !hostName.isEmpty else { return String(localized: "your Mac") }
        return hostName
    }

    /// spec §9 diagnostics deliverable: logs the same per-candidate detail `PairingScreen`'s
    /// "Details" disclosure shows, at `.error` (persisted without `sudo log config`) via the app's
    /// own `Log.net` — never secrets/proofs, just address/outcome/timing.
    nonisolated static func logConnectFailure(context: String, appError: AppError, attempts: [AddressAttemptResult]) {
        Log.net.error("\(context, privacy: .public) failed: \(appError.presentation.id, privacy: .public), \(attempts.count, privacy: .public) candidate(s) tried")
        for attempt in attempts {
            Log.net.error("\(context, privacy: .public) candidate \(attempt.address, privacy: .public): \(attempt.outcome, privacy: .public) (\(attempt.elapsedMs, privacy: .public) ms)")
        }
    }

    nonisolated static func mapErrorPayload(_ payload: ErrorPayload) -> AppError {
        switch payload.knownCode {
        case .authUntrusted: return .authUntrusted
        case .authRevoked: return .authRevoked
        case .pairingExpired: return .pairingExpired
        case .pairingInvalidProof: return .pairingWrongCode
        case .pairingTooManyDevices: return .pairingDeviceLimit
        case .rateLimited: return .rateLimited
        case .versionMismatch: return .versionAppOutdated
        case .macroBlockedByPolicy: return .macroBlocked
        case .alreadyTrusted: return .pairingAlreadyTrusted
        default: return .generic(code: payload.code)
        }
    }

    private static func hardwareModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce(into: "") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            partial += String(UnicodeScalar(UInt8(value)))
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }
}

/// `TrustedDeviceRecord.localAlias`, falling back to `name` — used wherever the Devices UI/error
/// copy wants "the" display name for a host.
private extension TrustedDeviceRecord {
    var displayName: String { localAlias ?? name }
}

/// A `SecIdentity` boxed as `@unchecked Sendable` so it can cross into `@Sendable`
/// `TaskGroup.addTask` closures — mirrors `AirMouseCrypto.GeneratedIdentity`'s own rationale:
/// Security.framework's CF handles are safe to hand across isolation domains as opaque,
/// effectively-immutable values.
private struct SendableSecIdentity: @unchecked Sendable {
    let value: SecIdentity
    init(_ value: SecIdentity) { self.value = value }
}
