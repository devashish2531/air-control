import Testing
import Foundation
@testable import AirMouseCore
import AirMouseCrypto

@Suite struct PairingWindowTests {
    @Test func opensAndIsOpenImmediately() throws {
        var window = PairingWindow()
        let now = Date()
        _ = try window.open(now: now)
        #expect(window.isOpen(now: now))
        #expect(window.isOpen(now: now.addingTimeInterval(59)))
    }

    @Test func expiresAfterSixtySeconds() throws {
        var window = PairingWindow()
        let now = Date()
        _ = try window.open(now: now)
        #expect(!window.isOpen(now: now.addingTimeInterval(60)))
        #expect(!window.isOpen(now: now.addingTimeInterval(120)))
    }

    @Test func closedWindowIsNeverOpen() {
        let window = PairingWindow()
        #expect(!window.isOpen(now: Date()))
    }

    @Test func regenerateIfExpiredProducesFreshSecretOnlyWhenExpired() throws {
        var window = PairingWindow()
        let start = Date()
        let original = try window.open(now: start)
        let notYetExpired = try window.regenerateIfExpired(now: start.addingTimeInterval(30))
        #expect(notYetExpired == nil)
        #expect(window.secret?.bytes == original.bytes)

        let refreshed = try window.regenerateIfExpired(now: start.addingTimeInterval(61))
        #expect(refreshed != nil)
        #expect(window.isOpen(now: start.addingTimeInterval(61)))
    }

    @Test func acceptedProofClosesWindow() throws {
        var window = PairingWindow()
        let now = Date()
        _ = try window.open(now: now)
        let outcome = window.recordProofAttempt(valid: true, now: now)
        #expect(outcome == .accepted)
        #expect(!window.isOpen(now: now))
    }

    @Test func wrongProofRetriesUpToThreeTimesThenLocksOut() throws {
        var window = PairingWindow()
        let now = Date()
        _ = try window.open(now: now)
        #expect(window.recordProofAttempt(valid: false, now: now) == .wrongProofRetry)
        #expect(window.recordProofAttempt(valid: false, now: now) == .wrongProofRetry)
        #expect(window.recordProofAttempt(valid: false, now: now) == .wrongProofLockedOut)
        #expect(!window.isOpen(now: now))
    }

    @Test func proofAgainstClosedWindowIsRejected() {
        var window = PairingWindow()
        #expect(window.recordProofAttempt(valid: true, now: Date()) == .rejected)
    }

    @Test func proofAgainstExpiredWindowIsRejected() throws {
        var window = PairingWindow()
        let now = Date()
        _ = try window.open(now: now)
        #expect(window.recordProofAttempt(valid: true, now: now.addingTimeInterval(61)) == .rejected)
    }

    @Test func hostProofRoundTripsWithClientProof() throws {
        var window = PairingWindow()
        let now = Date()
        let secret = try window.open(now: now)
        let clientFP = stubFingerprint(0x11)
        let hostFP = stubFingerprint(0x22)
        let hostID = Data(repeating: 0x33, count: 16)
        let nonce = Data(repeating: 0x44, count: 16)
        let exporter = Data(repeating: 0x55, count: 32)

        let clientProofData = try PairingClient.computeProof(
            secret: Data(secret.bytes),
            exporter: exporter,
            nonce: nonce,
            clientFingerprint: clientFP,
            hostFingerprint: hostFP,
            hostID: hostID
        )
        let binding = try PairingWindow.binding(exporter: exporter, nonce: nonce, clientFingerprint: clientFP, hostFingerprint: hostFP, hostID: hostID)
        #expect(window.verifyClientProof(clientProofData, binding: binding))

        let hostProof = window.computeHostProof(binding: binding)
        #expect(hostProof != nil)
        let verified = try PairingClient.verifyHostProof(
            hostProof!,
            secret: Data(secret.bytes),
            exporter: exporter,
            nonce: nonce,
            clientFingerprint: clientFP,
            hostFingerprint: hostFP,
            hostID: hostID
        )
        #expect(verified)
    }

    @Test func pairingURLComposesFromWindow() throws {
        var window = PairingWindow()
        _ = try window.open(now: Date())
        let url = try window.pairingURL(
            hostID: Data(repeating: 1, count: 16),
            hostName: "Test Mac",
            addresses: ["192.168.1.5"],
            tcpPort: 47800,
            fingerprint: Data(repeating: 2, count: 32)
        )
        #expect(url.hostName == "Test Mac")
        #expect(url.tcpPort == 47800)
        let formatted = try url.formatted()
        #expect(formatted.hasPrefix("airmouse://pair?"))
    }

    @Test func pairingURLThrowsWithoutOpenWindow() {
        let window = PairingWindow()
        #expect(throws: (any Error).self) {
            _ = try window.pairingURL(
                hostID: Data(repeating: 1, count: 16),
                hostName: "Test Mac",
                addresses: ["192.168.1.5"],
                tcpPort: 47800,
                fingerprint: Data(repeating: 2, count: 32)
            )
        }
    }
}
