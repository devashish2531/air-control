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
    private func attempt(_ address: String, succeeded: Bool = false, failure: TransportFailure? = nil, outcome: String = "timed out") -> AddressAttemptResult {
        AddressAttemptResult(address: address, outcome: outcome, elapsedMs: 4000, succeeded: succeeded, isTLSFailure: false, failure: failure)
    }

    // MARK: (a) never reached the Mac at all — `.unreachable`/`.timedOut`/`.closedBeforeReady`

    @Test func everyCandidateTimingOutMapsToHostUnreachable() {
        let attempts = [attempt("192.168.0.218", failure: .timedOut), attempt("fd01::1", failure: .timedOut)]
        let error = ConnectionManager.mapPairingError(TransportFailure.timedOut, attempts: attempts, hostName: "Marcus's Mac")
        #expect(error == .hostUnreachable(hostName: "Marcus's Mac"))
    }

    @Test func everyCandidateRefusedMapsToHostUnreachableOnReconnect() {
        let attempts = [attempt("192.168.0.218", failure: .unreachable, outcome: "unreachable")]
        let error = ConnectionManager.mapConnectError(TransportFailure.unreachable, hostName: "Marcus's Mac", attempts: attempts)
        #expect(error == .hostUnreachable(hostName: "Marcus's Mac"))
    }

    @Test func noAttemptsAtAllFallsBackToConnectionFailed() {
        // The 12 s overall watchdog fired before any candidate reported in at all.
        let error = ConnectionManager.mapConnectError(TransportFailure.unreachable, hostName: "Marcus's Mac", attempts: [])
        #expect(error == .connectionFailed(hostName: "Marcus's Mac"))
    }

    // MARK: (1) the Mac refuses an untrusted phone — `.tlsAlertFromPeer` → `.hostRefusedUntrusted`

    @Test func peerTLSAlertDuringPairingMapsToHostRefusedUntrusted() {
        let attempts = [attempt("192.168.0.218", failure: .tlsAlertFromPeer(description: "peer refused our certificate (status -9830)"), outcome: "peer refused our certificate (status -9830)")]
        let error = ConnectionManager.mapPairingError(TransportFailure.tlsAlertFromPeer(description: "peer refused our certificate (status -9830)"), attempts: attempts, hostName: "Marcus's Mac")
        #expect(error == .hostRefusedUntrusted)
    }

    @Test func peerTLSAlertDuringReconnectMapsToHostRefusedUntrusted() {
        let failure = TransportFailure.tlsAlertFromPeer(description: "peer refused our certificate (status -9830)")
        let attempts = [attempt("192.168.0.218", failure: failure, outcome: "peer refused our certificate (status -9830)")]
        let error = ConnectionManager.mapConnectError(failure, hostName: "Marcus's Mac", attempts: attempts)
        #expect(error == .hostRefusedUntrusted)
    }

    // MARK: (2) our own client identity can't sign — `.clientIdentityFailure` → `.tlsHandshakeFailed`

    @Test func clientIdentityFailureDuringPairingMapsToTLSHandshakeFailed() {
        let detail = "client identity did not complete the handshake within 4.0s after the peer's certificate was accepted"
        let attempts = [attempt("192.168.0.218", failure: .clientIdentityFailure(description: detail), outcome: detail)]
        let error = ConnectionManager.mapPairingError(TransportFailure.clientIdentityFailure(description: detail), attempts: attempts, hostName: "Marcus's Mac")
        #expect(error == .tlsHandshakeFailed(detail: detail))
    }

    @Test func clientIdentityFailureDuringReconnectMapsToTLSHandshakeFailed() {
        let detail = "client identity did not complete the handshake within 4.0s after the peer's certificate was accepted"
        let failure = TransportFailure.clientIdentityFailure(description: detail)
        let attempts = [attempt("192.168.0.218", failure: failure, outcome: detail)]
        let error = ConnectionManager.mapConnectError(failure, hostName: "Marcus's Mac", attempts: attempts)
        #expect(error == .tlsHandshakeFailed(detail: detail))
    }

    // MARK: (3) a stale trust record — `.peerCertificateMismatch` → pairing vs. reconnect wording

    @Test func peerCertificateMismatchDuringPairingMapsToFingerprintMismatch() {
        let failure = TransportFailure.peerCertificateMismatch(expected: "aabbccdd", actual: "11223344")
        let attempts = [attempt("192.168.0.218", failure: failure, outcome: "certificate mismatch")]
        let error = ConnectionManager.mapPairingError(failure, attempts: attempts, hostName: "Marcus's Mac")
        #expect(error == .pairingFingerprintMismatch)
    }

    @Test func peerCertificateMismatchDuringReconnectMapsToHostIdentityChanged() {
        let failure = TransportFailure.peerCertificateMismatch(expected: "aabbccdd", actual: "11223344")
        let attempts = [attempt("192.168.0.218", failure: failure, outcome: "certificate mismatch")]
        let error = ConnectionManager.mapConnectError(failure, hostName: "Marcus's Mac", attempts: attempts)
        #expect(error == .hostIdentityChanged)
        #expect(error != .tlsVerificationFailed(hostName: "Marcus's Mac")) // superseded by the more precise case above.
    }

    // MARK: A specific candidate outranks a generic terminal error (spec §9 diagnostics)

    @Test func oneSpecificCandidateOutranksOtherBoringTimeouts() {
        let failure = TransportFailure.peerCertificateMismatch(expected: "aabbccdd", actual: "11223344")
        let attempts = [
            attempt("192.168.0.10", failure: .timedOut),
            attempt("192.168.0.218", failure: failure, outcome: "certificate mismatch"),
        ]
        // The terminal error handed to `mapConnectError` is whichever candidate finished last
        // (here, a boring timeout) — the specific candidate should still win.
        let error = ConnectionManager.mapConnectError(TransportFailure.timedOut, hostName: "Marcus's Mac", attempts: attempts)
        #expect(error == .hostIdentityChanged)
    }

    // MARK: (c) local network permission denied

    @Test func localNetworkDeniedMapsTheSameWayInBothFlows() {
        #expect(ConnectionManager.mapPairingError(TransportFailure.localNetworkDenied, attempts: [], hostName: "Mac") == .localNetworkDenied)
        #expect(ConnectionManager.mapConnectError(TransportFailure.localNetworkDenied, hostName: "Mac", attempts: []) == .localNetworkDenied)
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

// MARK: - Stale-record replacement (spec item 4: same host id, regenerated Mac identity)

@Suite struct StaleRecordReplacementTests {
    private func makeKnownHosts() -> KnownHostsStore {
        KnownHostsStore(documentStore: DocumentStore(rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("StaleRecordReplacementTests-\(UUID().uuidString)")))
    }

    @Test func recordWithSameHostIDButDifferentFingerprintIsRemoved() async {
        let knownHosts = makeKnownHosts()
        let hostID = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let oldFingerprint = Fingerprint(bytes: [UInt8](repeating: 1, count: 32))!
        let newFingerprint = Fingerprint(bytes: [UInt8](repeating: 2, count: 32))!
        let oldRecord = TrustedDeviceRecord(fingerprint: oldFingerprint, name: "Old Mac", model: "Mac15,6", osVersion: "macOS 15.0", firstPaired: Date(), lastSeen: Date())
        await knownHosts.add(oldRecord)
        await knownHosts.setConnectionInfo(KnownHostConnectionInfo(tcpPort: 47800, udpPort: 47800, hostID: hostID), fingerprint: oldFingerprint)

        await ConnectionManager.replaceStaleRecord(forHostID: hostID, newFingerprint: newFingerprint, knownHosts: knownHosts)

        #expect(await knownHosts.lookup(fingerprint: oldFingerprint) == nil)
        #expect(await knownHosts.connectionInfo(fingerprint: oldFingerprint) == nil)
    }

    @Test func recordWithADifferentHostIDIsUntouched() async {
        let knownHosts = makeKnownHosts()
        let otherHostID = Data([0x01])
        let targetHostID = Data([0x02])
        let otherFingerprint = Fingerprint(bytes: [UInt8](repeating: 3, count: 32))!
        let newFingerprint = Fingerprint(bytes: [UInt8](repeating: 4, count: 32))!
        let otherRecord = TrustedDeviceRecord(fingerprint: otherFingerprint, name: "Unrelated Mac", model: "Mac15,6", osVersion: "macOS 15.0", firstPaired: Date(), lastSeen: Date())
        await knownHosts.add(otherRecord)
        await knownHosts.setConnectionInfo(KnownHostConnectionInfo(tcpPort: 47800, udpPort: 47800, hostID: otherHostID), fingerprint: otherFingerprint)

        await ConnectionManager.replaceStaleRecord(forHostID: targetHostID, newFingerprint: newFingerprint, knownHosts: knownHosts)

        #expect(await knownHosts.lookup(fingerprint: otherFingerprint) != nil)
    }

    @Test func recordAlreadyMatchingTheNewFingerprintIsUntouched() async {
        // Re-pairing with a Mac whose identity *hasn't* changed must not delete its own record.
        let knownHosts = makeKnownHosts()
        let hostID = Data([0xEE])
        let fingerprint = Fingerprint(bytes: [UInt8](repeating: 5, count: 32))!
        let record = TrustedDeviceRecord(fingerprint: fingerprint, name: "Same Mac", model: "Mac15,6", osVersion: "macOS 15.0", firstPaired: Date(), lastSeen: Date())
        await knownHosts.add(record)
        await knownHosts.setConnectionInfo(KnownHostConnectionInfo(tcpPort: 47800, udpPort: 47800, hostID: hostID), fingerprint: fingerprint)

        await ConnectionManager.replaceStaleRecord(forHostID: hostID, newFingerprint: fingerprint, knownHosts: knownHosts)

        #expect(await knownHosts.lookup(fingerprint: fingerprint) != nil)
    }
}
