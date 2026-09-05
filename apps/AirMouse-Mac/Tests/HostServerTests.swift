// HostServerTests — spec §3.1.1/§3.1.2 (Bonjour TXT composition), §3.2.1 (verify-block pinning
// policy), §5.1.5 (getifaddrs-sourced candidate addresses never include loopback).
@testable import Air_Mouse
import AirMouseCrypto
import AirMouseProtocol
import Foundation
import Testing

@Suite("HostServer")
struct HostServerTests {
    @Test("TXT record composed from fake host info round-trips through serialize()/parsing")
    func txtRecordComposition() throws {
        let hostID = Data(repeating: 0x11, count: 16)
        let fingerprint = Fingerprint(bytes: [UInt8](repeating: 0x22, count: 32))!
        let txt = try TXTRecord(
            supportedVersions: [ProtocolConstants.protocolVersion],
            hostName: "Devashish's Mac mini",
            hostID: hostID,
            fingerprintPrefix: Data(fingerprint.bytes.prefix(16)),
            machineModel: "Mac15,6",
            tcpPort: 47800,
            udpPort: 47800
        )
        let serialized = txt.serialize()
        #expect(serialized["v"] == "1")
        #expect(serialized["n"] == "Devashish's Mac mini")
        #expect(serialized["m"] == "Mac15,6")
        #expect(serialized["tp"] == "47800")
        #expect(serialized["up"] == "47800")

        // spec §3.1.2: each entry ≤ 255 bytes, total ≤ 400 bytes.
        for (key, value) in serialized {
            #expect(key.utf8.count + value.utf8.count <= 255)
        }
        let total = serialized.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
        #expect(total <= 400)

        let reparsed = try TXTRecord(parsing: serialized)
        #expect(reparsed.hostID == hostID)
        #expect(reparsed.supportsVersion(ProtocolConstants.protocolVersion))
    }

    @Test("QR payload composed from fake addresses fits the 512-byte limit and round-trips")
    func qrPayloadComposition() throws {
        let url = try PairingURL(
            version: ProtocolConstants.protocolVersion,
            hostID: Data(repeating: 0x33, count: 16),
            hostName: "Test Mac",
            addresses: ["172.20.10.5", "192.168.1.42", "fe80::aaaa"],
            tcpPort: 47800,
            fingerprint: Data(repeating: 0x44, count: 32),
            secret: Data(repeating: 0x55, count: 16)
        )
        let formatted = try url.formatted()
        #expect(formatted.utf8.count <= ProtocolConstants.qrURLMaxBytes)
        let parsed = try PairingURL.parse(formatted)
        #expect(parsed == url)
    }

    @Test("HostServerSettings.currentMachineModel returns a non-empty string")
    func machineModel() {
        #expect(!HostServerSettings.currentMachineModel().isEmpty)
    }

    @Test("HostServerSettings defaults to the spec's TCP/UDP port and non-loopback")
    func defaultSettings() {
        let settings = HostServerSettings(
            documentStore: DocumentStore(baseDirectory: FileManager.default.temporaryDirectory),
            hostNameProvider: { "Test" }
        )
        #expect(settings.tcpPort == UInt16(ProtocolConstants.defaultTCPPort))
        #expect(settings.udpPort == UInt16(ProtocolConstants.defaultUDPPort))
        #expect(settings.loopback == false)
    }

    // MARK: - PinningPolicy (spec §3.2.1's host verify-block decision table)

    @Test("PinningPolicy: a trusted, non-revoked fingerprint is always accepted")
    func pinningTrusted() {
        let fp = Fingerprint(bytes: [UInt8](repeating: 1, count: 32))!
        let decision = PinningPolicy.hostDecision(
            chainLength: 1, peerFingerprint: fp, trustedFingerprints: [fp],
            pairingWindowOpen: false, pendingConnectionCount: 0
        )
        #expect(decision == .trusted)
    }

    @Test("PinningPolicy: an unknown fingerprint is accepted as pendingPairing only while the window is open and under the pending cap")
    func pinningPendingPairing() {
        let fp = Fingerprint(bytes: [UInt8](repeating: 2, count: 32))!
        let openUnderCap = PinningPolicy.hostDecision(
            chainLength: 1, peerFingerprint: fp, trustedFingerprints: [],
            pairingWindowOpen: true, pendingConnectionCount: 1
        )
        #expect(openUnderCap == .pendingPairing)

        let openOverCap = PinningPolicy.hostDecision(
            chainLength: 1, peerFingerprint: fp, trustedFingerprints: [],
            pairingWindowOpen: true, pendingConnectionCount: PinningPolicy.maxPendingPairingConnections
        )
        #expect(openOverCap == .reject)

        let closed = PinningPolicy.hostDecision(
            chainLength: 1, peerFingerprint: fp, trustedFingerprints: [],
            pairingWindowOpen: false, pendingConnectionCount: 0
        )
        #expect(closed == .reject)
    }

    @Test("PinningPolicy: a chain length other than 1 is always rejected, even for a trusted fingerprint")
    func pinningRejectsWrongChainLength() {
        let fp = Fingerprint(bytes: [UInt8](repeating: 3, count: 32))!
        let decision = PinningPolicy.hostDecision(
            chainLength: 2, peerFingerprint: fp, trustedFingerprints: [fp],
            pairingWindowOpen: true, pendingConnectionCount: 0
        )
        #expect(decision == .reject)
    }

    @Test("currentInterfaceAddresses never returns the loopback address")
    func interfaceAddressesExcludeLoopback() {
        let addresses = HostServer.currentInterfaceAddresses()
        #expect(!addresses.contains("127.0.0.1"))
        #expect(!addresses.contains("::1"))
    }

    @Test("currentInterfaceAddresses never returns a zone-stripped link-local IPv6 address")
    func interfaceAddressesExcludeLinkLocalIPv6() {
        // spec §9 diagnostics deliverable: `fe80::…` with no `%zone` (the QR grammar forbids one)
        // can't be connected to from another device, so it must never reach the QR/pairing URL.
        let addresses = HostServer.currentInterfaceAddresses()
        #expect(!addresses.contains { $0.lowercased().hasPrefix("fe80") })
    }

    // MARK: - Non-loopback openPairingWindow() (repro for the reported hang)

    /// Races an operation against a fixed timeout, returning `nil` on timeout rather than hanging
    /// the test forever — used below so a genuine regression fails fast with a clear message
    /// instead of wedging the whole suite.
    private func withTimeout<T: Sendable>(seconds: TimeInterval, _ operation: @escaping @Sendable () async throws -> T) async -> T? {
        let result: T?? = try? await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }
        return result.flatMap { $0 }
    }

    /// Reproduces the field report: a *non-loopback* `HostServer` (real Keychain identity, real
    /// `getifaddrs`-sourced addresses, real fixed-shape TCP/UDP bind — just an ephemeral port and
    /// `bonjourEnabled: false` so the test process, which has no Local Network TCC grant of its own,
    /// can't stall on an unanswerable permission prompt) whose `openPairingWindow()` must resolve
    /// well within a generous timeout with a `PairingURL`-parsable string.
    @Test("openPairingWindow() resolves promptly in non-loopback mode")
    func openPairingWindowNonLoopbackResolves() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("HostServerTests-\(UUID().uuidString)")
        let documentStore = DocumentStore(baseDirectory: tempDir)

        let poster = RecordingEventPoster()
        let injector = EventInjector(poster: poster, startHeldInputWatchdog: false)
        let macroStore = MacroStore(documentStore: documentStore)
        let macroEngine = MacroEngine(store: macroStore, executor: MockMacroActionExecutor())
        let trustStore = TrustStore(documentStore: documentStore)
        let pairingService = PairingService()
        let udpHub = NWUDPHub()

        let sessionManager = SessionManager(
            eventInjector: injector,
            macroEngine: macroEngine,
            macroStore: macroStore,
            trustStore: trustStore,
            pairingService: pairingService,
            udpHub: udpHub,
            hostStateSnapshotProvider: {
                HostStateSnapshot(
                    naturalScrollEnabled: true,
                    displayTopology: .empty,
                    isPaused: false,
                    isAccessibilityTrusted: true,
                    frontmostAppBundleID: nil,
                    timestamp: Date()
                )
            },
            globalScriptsEnabledProvider: { false }
        )

        let settings = HostServerSettings(
            tcpPort: 0, // ephemeral — avoids colliding with a real, already-running helper on 47800.
            udpPort: 0,
            loopback: false, // exercises the real (non-loopback) identity + addressing path.
            bonjourEnabled: false, // see this test's/the flag's doc comment.
            persistIdentity: false, // ephemeral identity: never touch the developer's real Keychain identity from a test.
            documentStore: documentStore,
            hostNameProvider: { "HostServerTests Mac" }
        )
        let hostServer = HostServer(
            settings: settings,
            trustStore: trustStore,
            pairingService: pairingService,
            sessionManager: sessionManager,
            udpHub: udpHub
        )

        let started: Bool? = await withTimeout(seconds: 5) {
            await hostServer.start()
            return true
        }
        #expect(started != nil, "HostServer.start() did not complete within 5s in non-loopback mode")

        let outcome = await withTimeout(seconds: 5) { () async -> (value: String?, errorDescription: String?) in
            do {
                return (try await hostServer.openPairingWindow(), nil)
            } catch {
                return (nil, String(describing: error))
            }
        }
        let urlString = outcome?.value
        if let errorDescription = outcome?.errorDescription {
            Issue.record("openPairingWindow() threw: \(errorDescription)")
        }
        #expect(urlString != nil, "openPairingWindow() did not resolve within 5s in non-loopback mode")

        if let urlString {
            let parsed = try PairingURL.parse(urlString)
            #expect(parsed.tcpPort > 0)
        }
    }
}
