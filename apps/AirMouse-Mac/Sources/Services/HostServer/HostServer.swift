// HostServer — spec §3.1 (discovery/Bonjour/TXT), §3.2.1 (TLS config + verify block), §5.1.5
// (Bonjour registration + local-network privacy), §7.5/§7.6 (secure defaults, DoS limits); arch
// §3.3, §7.2 (TLS configuration sample). Owned by the networking agent (assignment:
// "Services/HostServer/").
//
// Creates/loads the host's P-256 identity, runs the TLS/TCP `NWListener` (control channel) and the
// UDP hub (motion channel, `NWDatagramChannel.swift`), advertises Bonjour, and accepts connections
// — handing each accepted, TLS-authenticated `NWConnection` to `SessionManager` to turn into an
// `AirMouseCore.HostSession`. Conforms to the shell's `HostServing` (`App/ServiceProtocols.swift`).
import AirMouseCore
import AirMouseCrypto
import AirMouseProtocol
import Foundation
import Network
import Security
import os

/// Where a listener currently stands, for the menu/UI (spec §5.1.5's local-network-denied guidance,
/// §5.1.2's firewall detection). Not part of the shell's `HostServing` protocol (that surface is
/// intentionally tiny) — exposed as a plain property on the concrete actor for the integration
/// agent to read if/when `AppEnvironment` grows a slot for it.
public enum HostServerNetworkStatus: Sendable, Equatable {
    case idle
    case starting
    case ready
    /// macOS 15's local-network privacy prompt denied Bonjour registration (spec §5.1.5,
    /// `kDNSServiceErr_PolicyDenied`). Manual-IP connections still work; only discovery is blocked.
    case localNetworkDenied
    case failed(description: String)
}

public actor HostServer: HostServing {
    /// Overridable via `AIRMOUSE_IDENTITY_LABEL` purely so a throwaway, alternate-port copy of the
    /// helper (used to verify a Keychain-identity fix without touching the real running helper's
    /// state — a legacy-tier item's ACL trusts a code signature, not a bundle id, so two differently
    /// signed processes sharing this label really could clobber each other's key) can target its own,
    /// isolated Keychain item. Every real launch path leaves this unset and gets the same fixed label
    /// as before.
    private var identityLabel: String {
        ProcessInfo.processInfo.environment["AIRMOUSE_IDENTITY_LABEL"] ?? "AirMouse Host Identity"
    }
    private let trustStore: TrustStore
    private let pairingService: PairingService
    private let sessionManager: SessionManager
    private let settings: HostServerSettings
    private let netQueue = DispatchQueue(label: "com.airmouse.helper.net", qos: .userInteractive)

    private var identity: GeneratedIdentity?
    private var hostID: Data = .init(repeating: 0, count: 16)
    private var tcpListener: NWListener?
    /// Shared with `SessionManager` (same instance, constructed once by `HostFeature.make`) so a
    /// session's `NWDatagramChannel` registration and this listener's receive loop agree.
    private let udpHub: NWUDPHub
    public private(set) var networkStatus: HostServerNetworkStatus = .idle

    public init(settings: HostServerSettings, trustStore: TrustStore, pairingService: PairingService, sessionManager: SessionManager, udpHub: NWUDPHub) {
        self.settings = settings
        self.trustStore = trustStore
        self.pairingService = pairingService
        self.sessionManager = sessionManager
        self.udpHub = udpHub
    }

    // MARK: - HostServing

    public func start() async {
        guard tcpListener == nil else { return }
        networkStatus = .starting
        do {
            let identity = try await loadOrCreateIdentity()
            self.identity = identity
            hostID = await loadOrCreateHostID()

            try await udpHub.start(port: settings.udpPort, loopbackOnly: settings.loopback)
            try startTCPListener(identity: identity)
            // integration task (out-of-scope fix, see report): `listener.start(queue:)` binds
            // asynchronously — `.port` reads back `0`, not nil, until the listener's state actually
            // reaches `.ready`, so both `registerBonjour`/`buildPairingURLString` (fixed port) and
            // `printLoopbackBanner` (ephemeral port) raced it and read a stale `0` here.
            await waitForListenerReady()

            if settings.loopback {
                // Contract for the `--loopback` cli/integration-test agent: no Bonjour, print the
                // resolved ports and an immediately-open pairing window's URL to stdout.
                await printLoopbackBanner()
            } else if settings.bonjourEnabled {
                try await registerBonjour(identity: identity)
            } else {
                // Non-loopback, Bonjour disabled — a test-only combination (`bonjourEnabled` is
                // `true` in every real launch path) that exercises the real Keychain identity, real
                // TCP/UDP binding, and real `getifaddrs` address enumeration without touching
                // Bonjour/mDNS, so a test process without its own Local Network TCC grant can't
                // stall here waiting on a permission prompt no one can answer.
                Log.net.info("HostServer: Bonjour registration skipped (bonjourEnabled = false)")
            }
            networkStatus = .ready
            // `.notice` (persisted to disk by default, unlike `.debug`/`.info`) so "is the helper
            // even listening" is answerable from `log show` without `sudo log config` first.
            Log.net.notice("HostServer: listening, tcp=\(self.tcpListener?.port?.rawValue ?? 0, privacy: .public) udp=\(self.udpHub.boundPort ?? 0, privacy: .public)")
        } catch {
            networkStatus = .failed(description: String(describing: error))
            Log.net.error("HostServer.start() failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func stop() async {
        tcpListener?.cancel()
        tcpListener = nil
        udpHub.stop()
        await sessionManager.closeAll(reason: .hostQuit)
        networkStatus = .idle
    }

    public var connectedSessions: [ConnectedSessionInfo] {
        get async { await sessionManager.connectedSessions }
    }

    public func openPairingWindow() async throws -> String {
        Log.net.debug("openPairingWindow: enter")
        _ = try await pairingService.openWindow()
        Log.net.debug("openPairingWindow: pairingService.openWindow() returned")
        let result = try await buildPairingURLString()
        Log.net.debug("openPairingWindow: buildPairingURLString() returned, len=\(result.count, privacy: .public)")
        return result
    }

    public func closePairingWindow() async {
        await pairingService.closeWindow()
    }

    public func disconnect(sessionID: String) async {
        await sessionManager.disconnect(sessionID: sessionID)
    }

    /// Extra surface beyond `HostServing`, for `PairingWindowView` to render "Waiting…" / "Device
    /// connecting…" / "Paired with <device>" / locked-out (spec §5.1.3) — reached via a best-effort
    /// downcast since the shell's DI slot is typed `any HostServing`.
    public func pairingServiceStatusForUI() async -> PairingService.Status {
        await pairingService.status
    }

    /// Extra surface beyond `HostServing` (same rationale as `pairingServiceStatusForUI()` above):
    /// the Diagnostics window's "Recent connection events" list (spec §9 diagnostics deliverable),
    /// reached via a best-effort downcast since the shell's DI slot is typed `any HostServing`.
    public func recentConnectionEvents() async -> [ConnectionEvent] {
        await sessionManager.recentConnectionEvents
    }

    // MARK: - Identity

    private func loadOrCreateIdentity() async throws -> GeneratedIdentity {
        if settings.loopback || !settings.persistIdentity {
            // `--loopback` (the CLI/integration-test path) launches this process headless, with no
            // GUI session to service a Keychain ACL prompt. A Keychain-persisted identity's ACL is
            // scoped to the *creating* process's code signature; any ad-hoc/debug rebuild changes
            // that signature, so a later launch's `SecKeyCreateSignature` (needed mid-TLS-handshake,
            // to sign the server's CertificateVerify) has to fall back to a `KeychainPromptAclSubject`
            // — i.e. it blocks on a `SecurityAgent` GUI prompt that never appears/gets answered here.
            // The raw TCP accept still succeeds (that's not gated on the key), so the client sees a
            // successful connect that then silently hangs mid-handshake, with nothing logged
            // server-side (the verify block for the *peer's* cert never even runs — the stall is on
            // signing our own cert, earlier in the state machine). A `--loopback` run is throwaway by
            // nature (fresh identity/fingerprint printed in the banner each launch), so there is no
            // reason to touch the Keychain at all: use the same in-memory, Keychain-free identity path
            // the unit/integration tests already use for both ends of the handshake.
            let hostID = await loadOrCreateHostID()
            return try IdentityFactory.makeEphemeralIdentity(
                commonName: "AirMouse Host \(hostID.b64u)",
                label: identityLabel
            )
        }
        let store = KeychainIdentityStore()
        if let found = try? store.loadIdentityWithTier(label: identityLabel) {
            // A legacy-tier key's default ACL trusts only the signature that created it: a rebuilt
            // (differently signed) helper can't use it — `SecKeyCreateSignature` would block on a
            // SecurityAgent prompt mid-TLS-handshake (see the `--loopback` note above). Probe once with
            // `canSign` (never blocks past `timeout`); only if that fails do we give up and replace it.
            // The `.legacyNoPrompt` ACL (`IdentityFactory`'s `SecACLSetContents(acl, nil, ...)`)
            // measurably avoids the *prompt*, but empirically still costs ~4s of one-time signature
            // re-validation the very first time a *newly re-signed* process touches the key (every
            // call after that first one is sub-20ms) — comfortably under `canSign`'s general-purpose
            // 2s default, so use a longer one here specifically to avoid misreading that one-time cost
            // as "unusable" and replacing a perfectly good identity (which is the whole defect this fix
            // exists to close).
            if store.canSign(found.identity, timeout: 8.0) {
                // REQUIRED FIX 3: a legacy-tier identity this process can already use gets migrated to
                // the Data Protection keychain in place — same key/certificate (fingerprint, and every
                // paired phone's pinned copy of it, unchanged) — so the defect actually gets fixed for
                // existing installs, not just new ones.
                if found.tier == .legacyNoPrompt, let migrated = store.migrateLegacyIdentityIfPossible(label: identityLabel) {
                    Log.net.notice("HostServer: migrated host identity from the legacy keychain to the Data Protection keychain (fingerprint unchanged)")
                    return migrated
                }
                if let wrapped = Self.wrap(secIdentity: found.identity, label: identityLabel, tier: found.tier) {
                    Log.net.notice("HostServer: host identity loaded (tier=\(found.tier.rawValue, privacy: .public))")
                    return wrapped
                }
            }
            Log.net.error("Host identity in the Keychain is not usable by this build (ACL/signature mismatch); replacing it. Paired devices must pair again.")
            try? store.deleteIdentity(label: identityLabel)
        }
        let hostID = await loadOrCreateHostID()
        do {
            let created = try IdentityFactory.makeIdentity(
                commonName: "AirMouse Host \(hostID.b64u)",
                label: identityLabel,
                preferSecureEnclave: false, // spec §3.2.1: host key uses `kSecAttrTokenID` none.
                accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            )
            Log.net.notice("HostServer: new host identity created (tier=\(created.tier.rawValue, privacy: .public))")
            return created
        } catch {
            // REQUIRED FIX 2, tier 3: neither the Data Protection keychain nor the legacy no-prompt
            // ACL worked (e.g. this process can't touch the Keychain at all). Fall back to an
            // in-memory identity so the helper still starts — paired devices will need to re-pair
            // every relaunch until a persistent tier becomes available, but that's strictly better
            // than not starting, or stalling on a prompt nobody can answer.
            Log.net.error("HostServer: no persistent Keychain tier is usable (\(String(describing: error), privacy: .public)); using an ephemeral host identity")
            return try IdentityFactory.makeEphemeralIdentity(
                commonName: "AirMouse Host \(hostID.b64u)",
                label: identityLabel
            )
        }
    }

    private static func wrap(secIdentity: SecIdentity, label: String, tier: IdentityStoreTier) -> GeneratedIdentity? {
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(secIdentity, &certificate)
        guard status == errSecSuccess, let certificate else { return nil }
        let der = SecCertificateCopyData(certificate) as Data
        return GeneratedIdentity(
            secIdentity: secIdentity,
            certificateDER: der,
            fingerprint: Fingerprint(certificateDER: der),
            backing: .keychainSecKey,
            label: label,
            tier: tier
        )
    }

    private struct HostIdentityDocument: Codable, Sendable {
        var hostID: Data
    }

    /// The stable, 16-random-byte install identifier (spec §3.1.2 TXT `id` / §3.1.3 QR `id`) —
    /// distinct from the TLS certificate identity above; persisted separately via the shell's
    /// `DocumentStore` (arch §6.3) rather than the Keychain, since it is not a secret.
    private func loadOrCreateHostID() async -> Data {
        let documentStore = settings.documentStore
        if let loaded = try? await documentStore.load(
            HostIdentityDocument.self,
            relativePath: "HostIdentity.json",
            schemaName: "host-identity",
            schemaVersion: 1
        ) {
            return loaded.hostID
        }
        let fresh = (try? SecureRandom.data(count: 16)) ?? Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        try? await documentStore.save(
            HostIdentityDocument(hostID: fresh),
            relativePath: "HostIdentity.json",
            schemaName: "host-identity",
            schemaVersion: 1
        )
        return fresh
    }

    // MARK: - TCP listener (control channel, spec §3.2.1, §7.2)

    private func startTCPListener(identity: GeneratedIdentity) throws {
        let tlsOptions = NWProtocolTLS.Options()
        let secOptions = tlsOptions.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(secOptions, .TLSv13)
        guard let secIdentityT = identity.secIdentityT else {
            throw HostServerError.identityUnavailable
        }
        sec_protocol_options_set_local_identity(secOptions, secIdentityT)
        sec_protocol_options_set_peer_authentication_required(secOptions, true)

        sec_protocol_options_set_verify_block(secOptions, { [weak self] _, trust, complete in
            guard let self else { complete(false); return }
            // Extract the (`Sendable`) fingerprint synchronously, before crossing into the actor —
            // `sec_trust_t` itself must not cross an isolation boundary (Swift 6 strict concurrency).
            guard let fingerprint = try? TLSPinning.fingerprint(from: trust) else {
                complete(false)
                return
            }
            // `sec_protocol_verify_complete_t` is an un-annotated ObjC block, so Swift imports it as
            // non-`Sendable`; box it so it can be handed to the `Task` below.
            let box = VerifyCompletionBox(complete)
            Task {
                let allowed = await self.verifyPeer(fingerprint: fingerprint)
                box.complete(allowed)
            }
        }, netQueue)

        let params = NWParameters(tls: tlsOptions)
        params.includePeerToPeer = false // spec §3.1.1.
        if settings.loopback {
            params.requiredInterfaceType = .loopback
        }

        let requestedPort = settings.tcpPort == 0 ? NWEndpoint.Port.any : (NWEndpoint.Port(rawValue: settings.tcpPort) ?? .any)
        let listener = try NWListener(using: params, on: requestedPort)
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { await self?.handleListenerState(state) }
        }
        tcpListener = listener
        listener.start(queue: netQueue)
    }

    /// Polls briefly for `tcpListener.port` to resolve to a real, non-zero port (or for
    /// `networkStatus` to report `.failed`/`.localNetworkDenied`) after `listener.start(queue:)`, which
    /// binds asynchronously. See the `start()` call site's comment (integration task, out-of-scope fix).
    private func waitForListenerReady() async {
        for _ in 0..<50 { // ~1s at 20ms steps — generous for a local bind, bounded so a genuine stall
            // (e.g. local-network-denied) doesn't hang `start()` forever.
            if let port = tcpListener?.port?.rawValue, port != 0 { return }
            switch networkStatus {
            case .failed, .localNetworkDenied: return
            default: break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// Races `channel.waitUntilReady()` against a generous, fixed timeout — a handshake that's
    /// actually going to succeed (including a legitimate reject-via-verify-block, which surfaces as
    /// `.failed` and resolves `waitUntilReady()` to `false` well within this) does so in well under a
    /// second; 10s only guards against a wedged/pathological connection leaking this `accept()` task
    /// forever.
    private func waitForChannelReady(_ channel: NWControlChannel, timeoutNanoseconds: UInt64 = 10_000_000_000) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await channel.waitUntilReady() }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    private func handleListenerState(_ state: NWListener.State) async {
        switch state {
        case .ready:
            if networkStatus != .localNetworkDenied {
                networkStatus = .ready
            }
        case .waiting(let error):
            if case .dns(let code) = error, code == kDNSServiceErr_PolicyDenied {
                networkStatus = .localNetworkDenied
                Log.net.error("HostServer: local network access denied (kDNSServiceErr_PolicyDenied)")
            }
        case .failed(let error):
            networkStatus = .failed(description: String(describing: error))
        default:
            break
        }
    }

    /// spec §3.2.1's host verify block: "accept iff (a) FP is in the trusted store and not revoked
    /// → `authenticated`, or (b) a Pairing window is open and pending-connection count < 2 →
    /// `unauthenticated`. Otherwise reject."
    private func verifyPeer(fingerprint: Fingerprint) async -> Bool {
        let trusted = await trustStore.trustedFingerprints()
        let pendingCount = await sessionManager.pendingSessionCount
        let windowOpen = await pairingService.isOpen()
        let decision = PinningPolicy.hostDecision(
            chainLength: PinningPolicy.requiredChainLength, // enforced by `TLSPinning.fingerprint` itself.
            peerFingerprint: fingerprint,
            trustedFingerprints: trusted,
            pairingWindowOpen: windowOpen,
            pendingConnectionCount: pendingCount
        )
        // `.notice` (persisted without `sudo log config`, same rationale as `accept(_:)`'s connection-
        // accepted line): the verify block's own decision, for diagnosing "phone can't connect" reports
        // without a debugger — fp prefix only (spec §7.4: FP prefixes are the one `.public` peer
        // identifier), plus whether it was already trusted, whether a pairing window was open, and the
        // resulting decision.
        Log.net.notice("HostServer: verifyPeer fp=\(fingerprint.shortLogPrefix, privacy: .public) known=\(trusted.contains(fingerprint), privacy: .public) windowOpen=\(windowOpen, privacy: .public) decision=\(String(describing: decision), privacy: .public)")
        return decision != .reject
    }

    private func accept(_ connection: NWConnection) async {
        // spec §7.6 / §11.3: "TCP connections (total) | 6 (4 authenticated + 2 pending)".
        let total = await sessionManager.totalSessionCount
        guard total < ProtocolConstants.maxAuthenticatedSessions + ProtocolConstants.maxPendingSessions else {
            connection.cancel()
            return
        }
        guard let identity else {
            connection.cancel()
            return
        }
        // `.notice` (persisted without `sudo log config`) — spec §9 diagnostics deliverable: this
        // is the first thing that should show up in `log show` when a phone can't pair, before any
        // TLS/pairing detail exists yet. Endpoint is redacted (§7.4: never a full IP at .info+).
        let peerDescription = Self.redactedEndpointDescription(connection.endpoint)
        Log.net.notice("HostServer: accepted TCP connection from \(peerDescription, privacy: .public)")
        await sessionManager.recordConnectionEvent("accepted: \(peerDescription)")

        let channel = NWControlChannel(connection: connection)
        await channel.start(on: netQueue)
        // `start(on:)` only *begins* the TLS handshake — `channel.peerFingerprint` (read by
        // `SessionManager.acceptConnection` immediately below, to classify the peer per spec
        // §3.2.1) can't see the peer's certificate chain until the handshake (verify block
        // included) actually finishes, so wait for that first. Without this wait, `peerFingerprint`
        // always reads `nil` here — silently misclassifying every peer, even an already-trusted one
        // reconnecting, as `.unknown` (see report). Bounded so a stalled handshake can't leak this
        // `accept()` task forever.
        guard await waitForChannelReady(channel) else {
            Log.tls.error("HostServer: TLS handshake failed or connection closed before ready, peer=\(peerDescription, privacy: .public)")
            await sessionManager.recordConnectionEvent("TLS handshake failed: \(peerDescription)")
            connection.cancel()
            return
        }
        let trusted = await trustStore.trustedFingerprints()
        let peerFingerprint = await channel.peerFingerprint
        let fingerprintPrefix = peerFingerprint.map { Redact.fingerprintPrefix($0.hexString) } ?? "none"
        let known = peerFingerprint.map { trusted.contains($0) } ?? false
        // Never the full fingerprint (spec §7.4/§5.7.3) — only the 8-hex prefix, which is `.public`.
        Log.tls.notice("HostServer: TLS handshake complete, peer=\(fingerprintPrefix, privacy: .public) known=\(known, privacy: .public)")
        await sessionManager.recordConnectionEvent("TLS ok: peer=\(fingerprintPrefix) (\(known ? "known" : "unknown"))")

        let windowSnapshot = await pairingService.currentSnapshot()
        await sessionManager.acceptConnection(
            channel: channel,
            trustedFingerprints: trusted,
            pairingWindow: windowSnapshot,
            hostIdentity: identity,
            hostID: hostID,
            hostName: settings.hostNameProvider(),
            udpPort: Int(udpHub.boundPort ?? UInt16(settings.udpPort))
        )
    }

    /// Redacted peer description for logging (spec §7.4: never a full IP address at `.info`+) —
    /// masks an IPv4 literal to its /24 network via `Redact.maskedIPv4`; IPv6 has no such helper
    /// today, so it's reported only by family, never the literal.
    private static func redactedEndpointDescription(_ endpoint: NWEndpoint) -> String {
        guard case .hostPort(let host, let port) = endpoint else { return "unknown" }
        switch host {
        case .ipv4(let address): return "\(Redact.maskedIPv4("\(address)")):\(port)"
        case .ipv6: return "ipv6:\(port)"
        case .name(let name, _): return "\(name):\(port)"
        @unknown default: return "unknown:\(port)"
        }
    }

    // MARK: - Bonjour (spec §3.1.1, §3.1.2, §5.1.5)

    private func registerBonjour(identity: GeneratedIdentity) async throws {
        guard let listener = tcpListener, let tcpPort = listener.port?.rawValue else {
            throw HostServerError.listenerNotReady
        }
        let udpPort = udpHub.boundPort ?? tcpPort
        let hostName = settings.hostNameProvider()
        let txt = try TXTRecord(
            supportedVersions: [ProtocolConstants.protocolVersion],
            hostName: hostName,
            hostID: hostID,
            fingerprintPrefix: identity.fingerprint.bytes.prefix(16).b64uData,
            machineModel: settings.machineModel(),
            tcpPort: Int(tcpPort),
            udpPort: Int(udpPort)
        )
        var nwTXT = NWTXTRecord()
        for (key, value) in txt.serialize() {
            nwTXT[key] = value
        }
        let service = NWListener.Service(name: hostName, type: BonjourServiceType.control, domain: BonjourServiceType.domain, txtRecord: nwTXT)
        listener.service = service
        listener.serviceRegistrationUpdateHandler = { change in
            if case .add(let endpoint) = change, case .service(let name, _, _, _) = endpoint {
                Log.net.notice("HostServer: Bonjour registered as \(name, privacy: .public)")
            }
        }
    }

    // MARK: - Pairing URL composition (spec §3.1.3)

    private func buildPairingURLString() async throws -> String {
        Log.net.debug("buildPairingURLString: enter (identity=\(self.identity != nil, privacy: .public), listener=\(self.tcpListener != nil, privacy: .public), port=\(self.tcpListener?.port?.rawValue ?? 0, privacy: .public))")
        guard let identity, let listener = tcpListener, let tcpPort = listener.port?.rawValue else {
            Log.net.error("buildPairingURLString: listenerNotReady")
            throw HostServerError.listenerNotReady
        }
        let udpPort = udpHub.boundPort ?? tcpPort
        Log.net.debug("buildPairingURLString: about to enumerate interface addresses (loopback=\(self.settings.loopback, privacy: .public))")
        let rawAddresses = settings.loopback ? ["127.0.0.1"] : Self.currentInterfaceAddresses()
        // `PairingURL`'s own validating initializer rejects more than `PairingURL.maxAddresses`
        // (spec §3.1.3: 1–6) outright — `PairingURL.truncatingToFit` only trims addresses to fit
        // the *byte-length* cap, by constructing that same validating initializer first, so it
        // throws before it ever gets a chance to shrink an over-long *count*. A real, non-loopback
        // Mac routinely has more than 6 non-loopback addresses once VPN (`utun*`), Personal
        // Hotspot (`bridge*`), AWDL/link-local IPv6, etc. are counted — that's exactly what made
        // `openPairingWindow()` throw `invalidPairingURL(field: "a", ...)` immediately on this
        // Mac (14 addresses), which `PairingContentView.openWindow()`'s `try?` then swallowed,
        // leaving `qrImage` (and so the QR area's `ProgressView()`) stuck forever — see the report.
        // `currentInterfaceAddresses()` already sorts best-candidate-first (hotspot/bridge → Wi-Fi
        // → Ethernet → link-local IPv6 last), so keeping the front of the list is exactly the
        // truncation the spec asks for ("the host truncates the address list").
        let addresses = Array(rawAddresses.prefix(PairingURL.maxAddresses))
        Log.net.debug("buildPairingURLString: addresses=\(addresses.count, privacy: .public) (of \(rawAddresses.count, privacy: .public) enumerated), tcpPort=\(tcpPort, privacy: .public), udpPort=\(udpPort, privacy: .public)")
        let url = try await pairingService.pairingURL(
            hostID: hostID,
            hostName: settings.hostNameProvider(),
            addresses: addresses,
            tcpPort: Int(tcpPort),
            udpPort: Int(udpPort),
            fingerprint: Data(identity.fingerprint.bytes)
        )
        Log.net.debug("buildPairingURLString: pairingService.pairingURL() returned")
        let formatted = try url.formatted()
        Log.net.debug("buildPairingURLString: formatted() returned")
        return formatted
    }

    /// Ordered candidate addresses for the QR/manual-fallback payload (spec §3.1.3: "hotspot/bridge
    /// → Wi-Fi → Ethernet → link-local IPv6 last"), read via `getifaddrs`.
    static func currentInterfaceAddresses() -> [String] {
        var result: [(address: String, rank: Int)] = []
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let firstAddr = ifaddrPointer else { return [] }
        defer { freeifaddrs(ifaddrPointer) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let addr = current.pointee.ifa_addr else { continue }
            let family = addr.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let socklen = family == UInt8(AF_INET) ? socklen_t(MemoryLayout<sockaddr_in>.size) : socklen_t(MemoryLayout<sockaddr_in6>.size)
            let getNameInfoResult = getnameinfo(addr, socklen, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            guard getNameInfoResult == 0 else { continue }
            var address = host.cStringValue
            // Strip the zone id (e.g. "%en0") IPv6 link-local addresses carry — the QR grammar
            // (spec §3.1.3) forbids it ("no brackets, no zone").
            if let percentIndex = address.firstIndex(of: "%") {
                address = String(address[address.startIndex..<percentIndex])
            }
            // spec §9 diagnostics deliverable: a zone-stripped IPv6 link-local address (`fe80::…`,
            // no `%zone` — the QR grammar forbids one) is useless to another device: nothing on
            // the client side can route to it without knowing which interface it's scoped to, so
            // it only wastes a connect-candidate slot there. Drop it here rather than merely
            // ranking it last, since a real Mac can have several of these (one per active
            // interface) and each one previously ate a stagger/timeout slot on the client for
            // nothing.
            guard !(family == UInt8(AF_INET6) && address.lowercased().hasPrefix("fe80")) else { continue }
            let ifName = String(cString: current.pointee.ifa_name)
            let rank = Self.addressRank(interfaceName: ifName, address: address)
            result.append((address, rank))
        }
        return result.sorted { $0.rank < $1.rank }.map(\.address)
    }

    /// Lower rank sorts first: hotspot/bridge, then Wi-Fi (`en0`), then other Ethernet, then
    /// everything else (spec §3.1.3) — link-local IPv6 no longer appears here at all (see the
    /// `fe80` filter above), so this only orders the remaining, genuinely-usable addresses.
    private static func addressRank(interfaceName: String, address: String) -> Int {
        if interfaceName.hasPrefix("bridge") || address.hasPrefix("172.20.10.") { return 0 }
        if interfaceName == "en0" { return 10 }
        if interfaceName.hasPrefix("en") { return 20 }
        return 50
    }

    // MARK: - --loopback banner (contract with the cli/integration-test agent)

    private func printLoopbackBanner() async {
        guard let tcpPort = tcpListener?.port?.rawValue else { return }
        let udpPort = udpHub.boundPort ?? tcpPort
        print("AIRMOUSE_TCP_PORT=\(tcpPort)")
        print("AIRMOUSE_UDP_PORT=\(udpPort)")
        fflush(stdout)
        if let urlString = try? await openPairingWindow() {
            print("AIRMOUSE_PAIR_URL=\(urlString)")
            fflush(stdout)
        }
    }
}

/// Wraps a `sec_protocol_verify_complete_t` (an un-annotated ObjC block, imported as non-`Sendable`)
/// so it can be captured by a `Task` closure. Safe: the block is Apple's own completion handler,
/// documented to be callable from any queue exactly once.
private struct VerifyCompletionBox: @unchecked Sendable {
    let complete: sec_protocol_verify_complete_t
    init(_ complete: @escaping sec_protocol_verify_complete_t) { self.complete = complete }
}

public enum HostServerError: Error, Sendable, Equatable {
    case identityUnavailable
    case listenerNotReady
}

/// Everything `HostServer` needs from the environment beyond the actors it's constructed with
/// (`HostFeature.make` is the single place these get filled in from `AppEnvironment`/`LaunchArguments`).
public struct HostServerSettings: Sendable {
    public var tcpPort: UInt16
    public var udpPort: UInt16
    public var loopback: Bool
    /// Whether `start()` registers the Bonjour (`_airmouse._tcp`) service in non-loopback mode.
    /// Always `true` in every real launch path (the app shell never sets this); a test-only escape
    /// hatch so a non-loopback `HostServer` can be exercised (real Keychain identity, real fixed/
    /// custom TCP+UDP bind, real `getifaddrs`-sourced addresses) inside a test process that has no
    /// Local Network TCC grant of its own to answer a permission prompt with — see `start()`.
    public var bonjourEnabled: Bool
    /// Whether the host identity is loaded from / stored in the Keychain. Tests set `false` to get an
    /// ephemeral identity: the Keychain path from an unsigned test host would trigger ACL prompts and
    /// could replace the developer's real host identity (invalidating paired devices).
    public var persistIdentity: Bool
    public var documentStore: DocumentStore
    public var hostNameProvider: @Sendable () -> String
    public var machineModel: @Sendable () -> String

    public init(
        tcpPort: UInt16 = UInt16(ProtocolConstants.defaultTCPPort),
        udpPort: UInt16 = UInt16(ProtocolConstants.defaultUDPPort),
        loopback: Bool = false,
        bonjourEnabled: Bool = true,
        persistIdentity: Bool = true,
        documentStore: DocumentStore,
        hostNameProvider: @escaping @Sendable () -> String,
        machineModel: @escaping @Sendable () -> String = { HostServerSettings.currentMachineModel() }
    ) {
        self.tcpPort = tcpPort
        self.udpPort = udpPort
        self.loopback = loopback
        self.bonjourEnabled = bonjourEnabled
        self.persistIdentity = persistIdentity
        self.documentStore = documentStore
        self.hostNameProvider = hostNameProvider
        self.machineModel = machineModel
    }

    public static func currentMachineModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return buffer.cStringValue
    }
}

private extension ArraySlice<UInt8> {
    var b64uData: Data { Data(self) }
}

private extension Array where Element == CChar {
    /// Decodes a null-terminated C string buffer as UTF-8, truncating at the first NUL byte.
    /// Replaces the deprecated `String(cString: [CChar])` array-based initializer.
    var cStringValue: String {
        let nullIndex = firstIndex(of: 0) ?? count
        return String(decoding: self[..<nullIndex].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
