// SessionManagerTests — spec §3.3 (trusted reconnect), §5.3 (event injection). Drives a full,
// real `AirControlCore.ClientSession` against a real `AirControlCore.HostSession` (inside
// `SessionManager`) over an in-memory `MockHostControlChannel` pair, with a `RecordingEventPoster`-
// backed `EventInjector` standing in for CoreGraphics — end to end, no real sockets/Keychain/CGEvent.
@testable import Air_Control
import AirControlCore
import AirControlCrypto
import AirControlProtocol
import Foundation
import Testing

/// A `DatagramChannel` that never receives anything — sufficient for `ClientSession.connect()`,
/// which only needs `datagramProvider` to succeed, not to actually carry motion in these tests.
private final class InertDatagramChannel: DatagramChannel, @unchecked Sendable {
    let incoming: AsyncStream<Data> = AsyncStream { _ in }
    func send(_ datagram: Data) throws {}
    func close() {}
}

@Suite("SessionManager", .serialized)
struct SessionManagerTests {
    private func fingerprint(_ seed: UInt8) -> Fingerprint {
        Fingerprint(bytes: [UInt8](repeating: seed, count: 32))!
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping () async -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Builds a `SessionManager` wired to a `RecordingEventPoster`-backed `EventInjector`, plus a
    /// connected `ClientSession` over an in-memory channel pair already past a trusted reconnect
    /// handshake (spec §3.3.1). Returns the poster so tests can assert on posted events.
    private func makeConnectedSession() async throws -> (manager: SessionManager, client: ClientSession, poster: RecordingEventPoster, tempDir: URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SessionManagerTests-\(UUID().uuidString)")
        let documentStore = DocumentStore(baseDirectory: tempDir)

        let poster = RecordingEventPoster()
        let injector = EventInjector(poster: poster, startHeldInputWatchdog: false)
        let macroStore = MacroStore(documentStore: documentStore)
        let macroEngine = MacroEngine(store: macroStore, executor: MockMacroActionExecutor())
        let trustStore = TrustStore(documentStore: documentStore)
        let pairingService = PairingService()
        let udpHub = NWUDPHub()

        let manager = SessionManager(
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

        let clientFingerprint = fingerprint(1)
        let hostFingerprint = fingerprint(2)
        let (hostChannel, clientChannel) = MockHostControlChannel.pair(
            hostSeesPeerFingerprint: clientFingerprint,
            clientSeesPeerFingerprint: hostFingerprint
        )

        let hostIdentity = try IdentityFactory.makeEphemeralIdentity(commonName: "AirControl Host SessionManagerTests")
        await manager.acceptConnection(
            channel: hostChannel,
            trustedFingerprints: [clientFingerprint], // spec §3.2.1(a): known, non-revoked → trusted reconnect.
            pairingWindow: nil,
            hostIdentity: hostIdentity,
            hostID: Data(repeating: 0x99, count: 16),
            hostName: "Test Host",
            udpPort: 47800
        )

        let client = ClientSession(
            control: clientChannel,
            datagramProvider: { _ in InertDatagramChannel() },
            clock: HostWallClock(),
            localFingerprint: clientFingerprint,
            device: Hello.Device(name: "Test iPhone", model: "iPhone16,1", os: "iOS 18.6", app: "1.0")
        )
        _ = try await client.connect()

        return (manager, client, poster, tempDir)
    }

    @Test("a click{tap} arrives as a left mouseDown followed by a mouseUp")
    func clickTapMapsToDownThenUp() async throws {
        let (_, client, poster, tempDir) = try await makeConnectedSession()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await client.sendClick(Click(button: .left, action: .tap, count: 1, modifiers: []))
        await waitUntil { poster.events.contains(where: { $0.kind == .leftMouseUp }) }

        #expect(poster.events.contains { $0.kind == .leftMouseDown })
        #expect(poster.events.contains { $0.kind == .leftMouseUp })
    }

    @Test("a key{down}/key{up} pair arrives as keyDown then keyUp for the same keycode")
    func keyDownUpMapsThrough() async throws {
        let (_, client, poster, tempDir) = try await makeConnectedSession()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await client.sendKey(Key(code: 0, action: .down, modifiers: [])) // kVK_ANSI_A
        await waitUntil { poster.events.contains(where: { $0.kind == .keyDown }) }
        try await client.sendKey(Key(code: 0, action: .up, modifiers: []))
        await waitUntil { poster.events.contains(where: { $0.kind == .keyUp }) }

        #expect(poster.events.contains { $0.kind == .keyDown && $0.keycode == 0 })
        #expect(poster.events.contains { $0.kind == .keyUp && $0.keycode == 0 })
    }

    @Test("text{s} arrives as a Unicode key event carrying the same string")
    func textMapsToUnicodeKeyEvent() async throws {
        let (_, client, poster, tempDir) = try await makeConnectedSession()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await client.sendText(Text(s: "hi", secure: false))
        await waitUntil { poster.events.contains(where: { $0.unicodeString == "hi" }) }

        #expect(poster.events.contains { $0.unicodeString == "hi" })
    }

    @Test("modifiers{flags} arrives as a flagsChanged-style keyDown for the modifier key")
    func modifiersMapThrough() async throws {
        let (_, client, poster, tempDir) = try await makeConnectedSession()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await client.sendModifiers(Modifiers(flags: [.shift]))
        await waitUntil { poster.events.contains(where: { $0.kind == .keyDown }) }

        #expect(poster.events.contains { $0.kind == .keyDown })
    }

    @Test("mediaKey{tap} arrives as a system-defined key event")
    func mediaKeyMapsThrough() async throws {
        let (_, client, poster, tempDir) = try await makeConnectedSession()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await client.sendMediaKey(MediaKeyMessage(key: .playPause, action: .tap))
        await waitUntil { poster.events.contains(where: { $0.kind == .systemDefinedKey }) }

        #expect(poster.events.contains { $0.kind == .systemDefinedKey && $0.nxKeyType == MediaKey.playPause.nxKeyType })
    }

    @Test("disconnecting releases all held input (a held click posts its mouseUp)")
    func disconnectReleasesHeldInput() async throws {
        let (manager, client, poster, tempDir) = try await makeConnectedSession()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await client.sendClick(Click(button: .left, action: .down, count: 1, modifiers: []))
        await waitUntil { poster.events.contains(where: { $0.kind == .leftMouseDown }) }

        let sessions = await manager.connectedSessions
        #expect(sessions.count == 1)
        if let id = sessions.first?.id {
            await manager.disconnect(sessionID: id)
        }
        await waitUntil { poster.events.contains(where: { $0.kind == .leftMouseUp }) }
        #expect(poster.events.contains { $0.kind == .leftMouseUp })
    }

    // MARK: - Diagnostics-and-UX deliverable: recent connection events ring buffer (spec §9)

    @Test("recentConnectionEvents records authentication, then disconnect, with a reason")
    func recentConnectionEventsRecordsLifecycle() async throws {
        let (manager, _, _, tempDir) = try await makeConnectedSession()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await waitUntil { await manager.recentConnectionEvents.contains { $0.message.hasPrefix("authenticated") } }
        let afterAuth = await manager.recentConnectionEvents
        #expect(afterAuth.contains { $0.message.hasPrefix("authenticated") })

        let sessions = await manager.connectedSessions
        #expect(sessions.count == 1)
        if let id = sessions.first?.id {
            await manager.disconnect(sessionID: id)
        }
        await waitUntil { await manager.recentConnectionEvents.contains { $0.message.hasPrefix("disconnected") } }
        let afterDisconnect = await manager.recentConnectionEvents
        #expect(afterDisconnect.contains { $0.message.hasPrefix("disconnected") })
    }

    @Test("a fresh pairing acceptance is recorded in the event ring buffer, distinct from a trusted-reconnect auth")
    func recentConnectionEventsRecordsPairingAcceptance() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SessionManagerTests-\(UUID().uuidString)")
        let documentStore = DocumentStore(baseDirectory: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let poster = RecordingEventPoster()
        let injector = EventInjector(poster: poster, startHeldInputWatchdog: false)
        let macroStore = MacroStore(documentStore: documentStore)
        let macroEngine = MacroEngine(store: macroStore, executor: MockMacroActionExecutor())
        let trustStore = TrustStore(documentStore: documentStore)
        let pairingService = PairingService()
        let udpHub = NWUDPHub()
        let manager = SessionManager(
            eventInjector: injector,
            macroEngine: macroEngine,
            macroStore: macroStore,
            trustStore: trustStore,
            pairingService: pairingService,
            udpHub: udpHub,
            hostStateSnapshotProvider: {
                HostStateSnapshot(naturalScrollEnabled: true, displayTopology: .empty, isPaused: false, isAccessibilityTrusted: true, frontmostAppBundleID: nil, timestamp: Date())
            },
            globalScriptsEnabledProvider: { false }
        )

        let hostIdentity = try IdentityFactory.makeEphemeralIdentity(commonName: "AirControl Host PairingRingBufferTest")
        let clientIdentity = try IdentityFactory.makeEphemeralIdentity(commonName: "AirControl Client PairingRingBufferTest")
        let hostID = Data(repeating: 0x77, count: 16)

        _ = try await pairingService.openWindow()
        let url = try await pairingService.pairingURL(
            hostID: hostID, hostName: "Test Host", addresses: ["127.0.0.1"],
            tcpPort: 47800, udpPort: 47800, fingerprint: Data(hostIdentity.fingerprint.bytes)
        )
        let windowSnapshot = await pairingService.currentSnapshot()

        let (hostChannel, clientChannel) = MockHostControlChannel.pair(
            hostSeesPeerFingerprint: clientIdentity.fingerprint,
            clientSeesPeerFingerprint: hostIdentity.fingerprint
        )
        // Both mocked ends report the same TLS exporter secret — real `NWControlChannel`s on the
        // two sides of one handshake would agree on this by construction (spec §3.2.3); the mock
        // needs it set explicitly on both to compute a proof the host side actually verifies.
        let sharedExporter = Data(repeating: 0xAB, count: 32)
        hostChannel.exporterOverride = sharedExporter
        clientChannel.exporterOverride = sharedExporter

        await manager.acceptConnection(
            channel: hostChannel,
            trustedFingerprints: [], // unknown peer — must prove against the open pairing window.
            pairingWindow: windowSnapshot,
            hostIdentity: hostIdentity,
            hostID: hostID,
            hostName: "Test Host",
            udpPort: 47800
        )

        let client = ClientSession(
            control: clientChannel,
            datagramProvider: { _ in InertDatagramChannel() },
            clock: HostWallClock(),
            localFingerprint: clientIdentity.fingerprint,
            device: Hello.Device(name: "Test iPhone", model: "iPhone16,1", os: "iOS 18.6", app: "1.0")
        )
        _ = try await client.pair(url: url, macroRevision: nil)

        await waitUntil { await manager.recentConnectionEvents.contains { $0.message.hasPrefix("pairing accepted") } }
        let events = await manager.recentConnectionEvents
        #expect(events.contains { $0.message.hasPrefix("pairing accepted") })
    }

    @Test("recordConnectionEvent caps the ring buffer at 20, dropping the oldest first")
    func recordConnectionEventCapsRingBuffer() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SessionManagerTests-\(UUID().uuidString)")
        let documentStore = DocumentStore(baseDirectory: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let manager = SessionManager(
            eventInjector: EventInjector(poster: RecordingEventPoster(), startHeldInputWatchdog: false),
            macroEngine: MacroEngine(store: MacroStore(documentStore: documentStore), executor: MockMacroActionExecutor()),
            macroStore: MacroStore(documentStore: documentStore),
            trustStore: TrustStore(documentStore: documentStore),
            pairingService: PairingService(),
            udpHub: NWUDPHub(),
            hostStateSnapshotProvider: {
                HostStateSnapshot(naturalScrollEnabled: true, displayTopology: .empty, isPaused: false, isAccessibilityTrusted: true, frontmostAppBundleID: nil, timestamp: Date())
            },
            globalScriptsEnabledProvider: { false }
        )

        for i in 0..<25 {
            await manager.recordConnectionEvent("event \(i)")
        }

        let events = await manager.recentConnectionEvents
        #expect(events.count == 20)
        #expect(events.first?.message == "event 5") // the oldest 5 were dropped.
        #expect(events.last?.message == "event 24")
    }
}
