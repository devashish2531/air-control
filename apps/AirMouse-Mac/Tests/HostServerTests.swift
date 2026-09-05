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
}
