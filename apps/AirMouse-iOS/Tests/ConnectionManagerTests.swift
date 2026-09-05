// Tests/ConnectionManagerTests.swift
// `ConnectionManager` behavior reachable without a real network handshake: malformed pairing URL
// handling (spec §3.1.3 E-PAIR-URL — fails before any TCP attempt), `forget`/`refreshKnownHostRows`
// bookkeeping, and app-lifecycle observers being inert while `.idle`. Full connect/pair/reconnect
// flows need a real `NWConnection` and are out of scope for a "simulator-safe, no network" suite.

import Foundation
import Testing
import UIKit
import AirMouseCore
import AirMouseCrypto
import AirMouseFilters
@testable import Air_Mouse

@MainActor
private func makeManager(userDefaultsSuite: String = "ConnectionManagerTests-\(UUID().uuidString)") -> ConnectionManager {
    let defaults = UserDefaults(suiteName: userDefaultsSuite)!
    let knownHosts = KnownHostsStore(documentStore: DocumentStore(rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("ConnectionManagerTests-\(UUID().uuidString)")))
    let identity = try! IdentityFactory.makeEphemeralIdentity(commonName: "AirMouse Test Client")
    return ConnectionManager(
        knownHosts: knownHosts,
        userSettings: UserSettings(defaults: defaults),
        diagnostics: DiagnosticsModel(),
        idleTimer: IdleTimer(),
        haptics: UIKitHapticsService(isHapticsEnabled: false, isSoundEnabled: false, supportsHaptics: false),
        clock: ManualClock(),
        clientIdentity: identity
    )
}

@MainActor
private func waitUntil(timeout: TimeInterval = 2.0, _ predicate: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !predicate() {
        if Date() >= deadline { return predicate() }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return true
}

@MainActor
@Suite struct ConnectionManagerTests {
    // MARK: - Pairing URL validation (spec §3.1.3 / §9 E-PAIR-URL)

    @Test func garbageURLFailsBeforeAnyConnectionAttempt() async {
        let manager = makeManager()
        await manager.pair(urlString: "not a url at all")

        #expect(manager.pairingProgress == .failed(.pairingURLInvalid))
        // No connection attempt means the shell connection state is untouched.
        #expect(manager.connectionState == .idle)
    }

    @Test func wrongSchemeURLFailsTheSameWay() async {
        let manager = makeManager()
        await manager.pair(urlString: "https://example.com/not-a-pairing-link")

        #expect(manager.pairingProgress == .failed(.pairingURLInvalid))
    }

    @Test func resetPairingProgressReturnsToIdle() async {
        let manager = makeManager()
        await manager.pair(urlString: "garbage")
        #expect(manager.pairingProgress != .idle)

        manager.resetPairingProgress()
        #expect(manager.pairingProgress == .idle)
    }

    // MARK: - Known-hosts bookkeeping

    @Test func forgetRemovesTheHostFromKnownHostRows() async {
        let manager = makeManager()
        let fingerprint = Fingerprint(bytes: [UInt8](repeating: 7, count: 32))!
        let record = TrustedDeviceRecord(fingerprint: fingerprint, name: "Test Mac", model: "Mac15,6", osVersion: "macOS 15.0", firstPaired: Date(), lastSeen: Date())
        await manager.knownHosts.add(record)
        await manager.refreshKnownHostRows()
        #expect(manager.knownHostRows.map(\.id) == [record.id])

        await manager.forget(record)

        #expect(manager.knownHostRows.isEmpty)
        #expect(await manager.knownHosts.lookup(fingerprint: fingerprint) == nil)
    }

    @Test func connectWithNoLastUsedHostIsANoOp() async {
        let manager = makeManager()
        await manager.connect() // nothing saved as "last used" — must not crash or hang
        #expect(manager.connectionState == .idle)
        #expect(manager.activeSession == nil)
    }

    @Test func disconnectWithNoActiveSessionIsANoOp() async {
        let manager = makeManager()
        await manager.disconnect()
        #expect(manager.connectionState == .idle)
    }

    // MARK: - App lifecycle observers (spec §4.5.5) are inert outside `.connected`

    @Test func backgroundingWhileIdleDoesNotChangeConnectionState() async {
        let manager = makeManager()
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        _ = await waitUntil(timeout: 0.3) { false } // let the notification dispatch settle
        #expect(manager.connectionState == .idle)
    }

    @Test func foregroundingWhileIdleDoesNotChangeConnectionState() async {
        let manager = makeManager()
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        _ = await waitUntil(timeout: 0.3) { false }
        #expect(manager.connectionState == .idle)
    }
}
