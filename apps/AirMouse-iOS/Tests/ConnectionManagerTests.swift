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
import AirMouseProtocol
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

// MARK: - Diagnostics-and-UX deliverable: link-local filtering + error mapping

@Suite struct AddressFilteringTests {
    @Test func zoneStrippedLinkLocalIPv6IsDropped() {
        #expect(!ConnectionManager.isUsableCandidateAddress("fe80::1"))
        #expect(!ConnectionManager.isUsableCandidateAddress("FE80::AAAA:BBBB:CCCC:DDDD"))
        #expect(!ConnectionManager.isUsableCandidateAddress("fe80::abcd:1234"))
    }

    @Test func linkLocalIPv6WithAZoneIsKept() {
        // Defensive: today's QR/lastKnown grammar never carries one, but if it ever did, a zoned
        // literal is actually connectable and shouldn't be thrown away.
        #expect(ConnectionManager.isUsableCandidateAddress("fe80::1%en0"))
    }

    @Test func ordinaryAddressesAreKept() {
        #expect(ConnectionManager.isUsableCandidateAddress("192.168.0.218"))
        #expect(ConnectionManager.isUsableCandidateAddress("fd01::1"))
        #expect(ConnectionManager.isUsableCandidateAddress("10.0.0.5"))
    }
}

@Suite struct ConnectionManagerErrorMappingTests {
    private func attempt(_ address: String, succeeded: Bool = false, isTLSFailure: Bool = false, outcome: String = "timed out") -> AddressAttemptResult {
        AddressAttemptResult(address: address, outcome: outcome, elapsedMs: 4000, succeeded: succeeded, isTLSFailure: isTLSFailure)
    }

    // MARK: (a) never reached the Mac at all

    @Test func everyCandidateTimingOutMapsToHostUnreachable() {
        let attempts = [attempt("192.168.0.218"), attempt("fd01::1")]
        let error = ConnectionManager.mapPairingError(TransportError.timedOut, attempts: attempts, hostName: "Marcus's Mac")
        #expect(error == .hostUnreachable(hostName: "Marcus's Mac"))
    }

    @Test func everyCandidateRefusedMapsToHostUnreachableOnReconnect() {
        let attempts = [attempt("192.168.0.218", outcome: "Connection refused")]
        let error = ConnectionManager.mapConnectError(TransportError.connectionFailed("Connection refused"), hostName: "Marcus's Mac", attempts: attempts)
        #expect(error == .hostUnreachable(hostName: "Marcus's Mac"))
    }

    @Test func noAttemptsAtAllFallsBackToConnectionFailed() {
        // The 12 s overall watchdog fired before any candidate reported in at all.
        let error = ConnectionManager.mapConnectError(TransportError.connectionFailed("no candidates"), hostName: "Marcus's Mac", attempts: [])
        #expect(error == .connectionFailed(hostName: "Marcus's Mac"))
    }

    // MARK: (b) TLS handshake failed / fingerprint mismatch

    @Test func tlsFailureDuringPairingMapsToFingerprintMismatch() {
        let attempts = [attempt("192.168.0.218", isTLSFailure: true, outcome: "TLS handshake failed: badCert")]
        let error = ConnectionManager.mapPairingError(TransportError.tlsHandshakeFailed("badCert"), attempts: attempts, hostName: "Marcus's Mac")
        #expect(error == .pairingFingerprintMismatch)
    }

    @Test func tlsFailureDuringReconnectMapsToTLSVerificationFailed() {
        let attempts = [attempt("192.168.0.218", isTLSFailure: true, outcome: "TLS handshake failed: badCert")]
        let error = ConnectionManager.mapConnectError(TransportError.tlsHandshakeFailed("badCert"), hostName: "Marcus's Mac", attempts: attempts)
        #expect(error == .tlsVerificationFailed(hostName: "Marcus's Mac"))
        #expect(error != .pairingFingerprintMismatch) // distinct from the pairing-time copy.
    }

    // MARK: (c) local network permission denied

    @Test func localNetworkDeniedMapsTheSameWayInBothFlows() {
        #expect(ConnectionManager.mapPairingError(TransportError.localNetworkDenied, attempts: [], hostName: "Mac") == .localNetworkDenied)
        #expect(ConnectionManager.mapConnectError(TransportError.localNetworkDenied, hostName: "Mac", attempts: []) == .localNetworkDenied)
    }

    // MARK: (d)/(e) host said proof invalid vs. secret expired — distinct AppErrors

    @Test func wireInvalidProofMapsToWrongCodeNotExpired() {
        let payload = ErrorPayload(code: ErrorCode.pairingInvalidProof.rawValue, message: "invalid proof", fatal: true)
        #expect(ConnectionManager.mapErrorPayload(payload) == .pairingWrongCode)
    }

    @Test func wireExpiredMapsToPairingExpired() {
        let payload = ErrorPayload(code: ErrorCode.pairingExpired.rawValue, message: "expired", fatal: true)
        #expect(ConnectionManager.mapErrorPayload(payload) == .pairingExpired)
    }

    @Test func coreInvalidProofDuringPairingMapsToWrongCodeNotExpired() {
        let error = ConnectionManager.mapPairingError(CoreError.pairingInvalidProof, attempts: [], hostName: "Mac")
        #expect(error == .pairingWrongCode)
        #expect(error != .pairingExpired)
    }

    @Test func coreExpiredDuringPairingMapsToPairingExpired() {
        let error = ConnectionManager.mapPairingError(CoreError.pairingExpired, attempts: [], hostName: "Mac")
        #expect(error == .pairingExpired)
    }
}
