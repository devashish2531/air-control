// Tests/PairingTests.swift
// Pairing-URL-shaped edge cases through `ConnectionManager.pair(urlString:)` (spec §3.1.3 /
// §9 E-PAIR-URL) and `PairingProgress`'s state semantics for `PairingScreen`. Deep-link routing
// (`routePairing(url:)`) is exercised as a thin wrapper over the same `pair(urlString:)` path.
// No network: every case here is rejected (or reset) before any `NWConnection` is opened.

import Foundation
import Testing
import AirControlCore
import AirControlCrypto
import AirControlFilters
@testable import Air_Control

@MainActor
private func makeManager() -> ConnectionManager {
    let knownHosts = KnownHostsStore(documentStore: DocumentStore(rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("PairingTests-\(UUID().uuidString)")))
    let identity = try! IdentityFactory.makeEphemeralIdentity(commonName: "AirControl Test Client")
    return ConnectionManager(
        knownHosts: knownHosts,
        userSettings: UserSettings(defaults: UserDefaults(suiteName: "PairingTests-\(UUID().uuidString)")!),
        diagnostics: DiagnosticsModel(),
        idleTimer: IdleTimer(),
        haptics: UIKitHapticsService(isHapticsEnabled: false, isSoundEnabled: false, supportsHaptics: false),
        clock: ManualClock(),
        clientIdentity: identity
    )
}

@MainActor
@Suite struct PairingTests {
    // MARK: - Malformed/incomplete pairing URLs (spec §3.1.3, §3.2.6 "missing/malformed required params → E-PAIR-URL")

    @Test func plainTextIsNotAPairingURL() async {
        let manager = makeManager()
        await manager.pair(urlString: "1234")
        #expect(manager.pairingProgress == .failed(.pairingURLInvalid))
    }

    @Test func rightSchemeMissingRequiredParamsIsRejected() async {
        let manager = makeManager()
        // `aircontrol://pair` with no query at all — missing every required param.
        await manager.pair(urlString: "aircontrol://pair")
        #expect(manager.pairingProgress == .failed(.pairingURLInvalid))
    }

    @Test func wrongHostInTheRightSchemeIsRejected() async {
        let manager = makeManager()
        await manager.pair(urlString: "aircontrol://not-pair?v=1")
        #expect(manager.pairingProgress == .failed(.pairingURLInvalid))
    }

    @Test func oversizedURLIsRejected() async {
        let manager = makeManager()
        // spec §3.1.3 / §11.3: "Total URL length SHALL be ≤ 512 bytes."
        let hugeName = String(repeating: "a", count: 600)
        await manager.pair(urlString: "aircontrol://pair?v=1&id=AAAAAAAAAAAAAAAAAAAAAA&n=\(hugeName)&a=10.0.0.1&p=47800&fp=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&s=AAAAAAAAAAAAAAAAAAAAAA")
        #expect(manager.pairingProgress == .failed(.pairingURLInvalid))
    }

    // MARK: - E-PAIR-URL is the exact spec §9 copy id

    @Test func pairingURLInvalidMapsToTheSpecCode() {
        #expect(AppError.pairingURLInvalid.presentation.id == "E-PAIR-URL")
    }

    // MARK: - `PairingProgress` state semantics `PairingScreen` renders

    @Test func progressStatesCarryTheirAssociatedData() {
        #expect(PairingProgress.connecting(hostName: "Devashish's Mac mini") == .connecting(hostName: "Devashish's Mac mini"))
        #expect(PairingProgress.connecting(hostName: "A") != .connecting(hostName: "B"))
        #expect(PairingProgress.verifying(hostName: "A") != .paired(hostName: "A"))
        #expect(PairingProgress.failed(.pairingExpired) == .failed(.pairingExpired))
        #expect(PairingProgress.failed(.pairingExpired) != .failed(.pairingFingerprintMismatch))
    }

    @Test func resetAlwaysReturnsToIdleRegardlessOfPriorState() async {
        let manager = makeManager()
        await manager.pair(urlString: "garbage")
        manager.resetPairingProgress()
        #expect(manager.pairingProgress == .idle)

        // Idempotent — resetting an already-idle manager is a no-op, not a crash.
        manager.resetPairingProgress()
        #expect(manager.pairingProgress == .idle)
    }

    // MARK: - Deep-link routing (`PairingRouting.routePairing(url:)`)

    @Test func routePairingForwardsToPairAndFailsTheSameWayOnGarbage() async {
        let manager = makeManager()
        let url = URL(string: "aircontrol://pair?v=1")!

        manager.routePairing(url: url)
        // `routePairing` fires an unstructured `Task` internally; give it a moment to land.
        var iterations = 0
        while manager.pairingProgress == .idle, iterations < 200 {
            try? await Task.sleep(nanoseconds: 5_000_000)
            iterations += 1
        }

        #expect(manager.pairingProgress == .failed(.pairingURLInvalid))
    }
}
