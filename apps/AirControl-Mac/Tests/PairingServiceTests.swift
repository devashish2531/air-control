// PairingServiceTests — spec §3.1.3 (QR payload), §3.1.4 (60 s window/regeneration), §5.1.3 status.
@testable import Air_Control
import Foundation
import Testing

@Suite("PairingService")
struct PairingServiceTests {
    @Test("openWindow reports .waiting and produces a well-formed pairing URL")
    func openWindowAndURL() async throws {
        let service = PairingService()
        #expect(await service.status == .closed)
        try await service.openWindow()
        #expect(await service.status == .waiting)
        #expect(await service.isOpen())

        let url = try await service.pairingURL(
            hostID: Data(repeating: 0xAB, count: 16),
            hostName: "Devashish's Mac mini",
            addresses: ["192.168.1.20", "fe80::1"],
            tcpPort: 47800,
            udpPort: 47800,
            fingerprint: Data(repeating: 0xCD, count: 32)
        )
        #expect(url.hostName == "Devashish's Mac mini")
        #expect(url.addresses == ["192.168.1.20", "fe80::1"])
        #expect(url.tcpPort == 47800)
        let formatted = try url.formatted()
        #expect(formatted.hasPrefix("aircontrol://pair?"))
        #expect(formatted.utf8.count <= 512)
    }

    @Test("closeWindow invalidates the secret and reports .closed")
    func closeWindow() async throws {
        let service = PairingService()
        try await service.openWindow()
        #expect(await service.isOpen())
        await service.closeWindow()
        #expect(!(await service.isOpen()))
        #expect(await service.status == .closed)
    }

    @Test("markConsumedByPairingSuccess closes the window and reports .paired")
    func markConsumed() async throws {
        let service = PairingService()
        try await service.openWindow()
        await service.markConsumedByPairingSuccess(deviceName: "Devashish's iPhone")
        #expect(!(await service.isOpen()))
        #expect(await service.status == .paired(deviceName: "Devashish's iPhone"))
    }

    @Test("noteLockedOut reports .lockedOut without requiring the window to still be open")
    func lockedOut() async throws {
        let service = PairingService()
        try await service.openWindow()
        await service.noteLockedOut()
        #expect(await service.status == .lockedOut)
    }

    @Test("regenerateIfExpired mints a fresh secret once the window has expired")
    func regeneratesOnExpiry() async throws {
        let service = PairingService()
        let originalSecret = try await service.openWindow()
        // 61 s later — past the 60 s lifetime (spec §3.1.4).
        let later = Date().addingTimeInterval(61)
        let regenerated = try await service.regenerateIfExpired(now: later)
        #expect(regenerated != nil)
        #expect(regenerated?.bytes != originalSecret.bytes)
        #expect(await service.isOpen(now: later))
    }

    @Test("regenerateIfExpired does nothing while the current secret is still valid")
    func doesNotRegenerateEarly() async throws {
        let service = PairingService()
        try await service.openWindow()
        let soon = Date().addingTimeInterval(5)
        let regenerated = try await service.regenerateIfExpired(now: soon)
        #expect(regenerated == nil)
    }

    @Test("currentSnapshot is nil when no window is open, non-nil when one is")
    func snapshot() async throws {
        let service = PairingService()
        #expect(await service.currentSnapshot() == nil)
        try await service.openWindow()
        #expect(await service.currentSnapshot() != nil)
    }
}
