import Testing
@testable import AirMouseCrypto

@Suite struct PinningPolicyTests {
    private let fpA = Fingerprint(certificateDER: [1])
    private let fpB = Fingerprint(certificateDER: [2])

    @Test func hostTrustsKnownFingerprint() {
        let decision = PinningPolicy.hostDecision(
            chainLength: 1,
            peerFingerprint: fpA,
            trustedFingerprints: [fpA],
            pairingWindowOpen: false,
            pendingConnectionCount: 0
        )
        #expect(decision == .trusted)
    }

    @Test func hostAllowsPendingPairingWhenWindowOpenAndRoomAvailable() {
        let decision = PinningPolicy.hostDecision(
            chainLength: 1,
            peerFingerprint: fpB,
            trustedFingerprints: [fpA],
            pairingWindowOpen: true,
            pendingConnectionCount: 1
        )
        #expect(decision == .pendingPairing)
    }

    @Test func hostRejectsWhenPendingSlotsFull() {
        let decision = PinningPolicy.hostDecision(
            chainLength: 1,
            peerFingerprint: fpB,
            trustedFingerprints: [fpA],
            pairingWindowOpen: true,
            pendingConnectionCount: PinningPolicy.maxPendingPairingConnections
        )
        #expect(decision == .reject)
    }

    @Test func hostRejectsUnknownFingerprintWithoutPairingWindow() {
        let decision = PinningPolicy.hostDecision(
            chainLength: 1,
            peerFingerprint: fpB,
            trustedFingerprints: [fpA],
            pairingWindowOpen: false,
            pendingConnectionCount: 0
        )
        #expect(decision == .reject)
    }

    @Test func hostRejectsWrongChainLengthEvenIfTrusted() {
        let decision = PinningPolicy.hostDecision(
            chainLength: 2,
            peerFingerprint: fpA,
            trustedFingerprints: [fpA],
            pairingWindowOpen: false,
            pendingConnectionCount: 0
        )
        #expect(decision == .reject)

        let zeroChain = PinningPolicy.hostDecision(
            chainLength: 0,
            peerFingerprint: fpA,
            trustedFingerprints: [fpA],
            pairingWindowOpen: true,
            pendingConnectionCount: 0
        )
        #expect(zeroChain == .reject)
    }

    @Test func clientAcceptsExactPinnedFingerprint() {
        #expect(PinningPolicy.clientAccepts(chainLength: 1, peerFingerprint: fpA, pinnedFingerprint: fpA))
    }

    @Test func clientRejectsMismatchedFingerprint() {
        #expect(PinningPolicy.clientAccepts(chainLength: 1, peerFingerprint: fpA, pinnedFingerprint: fpB) == false)
    }

    @Test func clientRejectsWrongChainLength() {
        #expect(PinningPolicy.clientAccepts(chainLength: 2, peerFingerprint: fpA, pinnedFingerprint: fpA) == false)
    }

    @Test func maxPendingPairingConnectionsMatchesSpec() {
        // spec §7.6, §11.3: "Pending pairing connections | 2".
        #expect(PinningPolicy.maxPendingPairingConnections == 2)
    }
}
