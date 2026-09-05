// Tests/NetworkTransportTests.swift
// `BonjourBrowser`'s TXT → `DiscoveredHost` parsing, including the R-10 cross-talk guard (spec
// §3.1.1: "a browse result whose TXT lacks `v` or whose `v` list does not include a version the
// client speaks is hidden from the Devices list") — via the pure helper
// `BonjourBrowser.discoveredHost(txtDictionary:endpoint:)`, since `NWBrowser.Result` itself has no
// public initializer a test could construct. Also `TransportError` sanity.

import Foundation
import Network
import Testing
import AirMouseProtocol
@testable import Air_Mouse

private let testEndpoint = NWEndpoint.hostPort(host: "10.0.0.5", port: 47800)

private func validTXT(version: String = "1") -> [String: String] {
    [
        "v": version,
        "n": "Devashish's Mac mini",
        "id": Data([UInt8](repeating: 0xAB, count: 16)).b64u,
        "fp": Data([UInt8](repeating: 0xCD, count: 16)).b64u,
        "m": "Mac15,6",
        "tp": "47800",
        "up": "47800",
    ]
}

@Suite struct NetworkTransportTests {
    @Test func validTXTRecordParsesIntoADiscoveredHost() {
        let host = BonjourBrowser.discoveredHost(txtDictionary: validTXT(), endpoint: testEndpoint)
        #expect(host?.name == "Devashish's Mac mini")
        #expect(host?.machineModel == "Mac15,6")
        #expect(host?.tcpPort == 47800)
        #expect(host?.udpPort == 47800)
        #expect(host?.supportedVersions == [1])
        #expect(host?.id == Data([UInt8](repeating: 0xAB, count: 16)))
    }

    @Test func missingVersionKeyIsHiddenPerR10() {
        var dict = validTXT()
        dict.removeValue(forKey: "v")
        #expect(BonjourBrowser.discoveredHost(txtDictionary: dict, endpoint: testEndpoint) == nil)
    }

    @Test func unsupportedVersionIsHiddenPerR10() {
        // This build speaks `ProtocolConstants.protocolVersion` (1); advertise only a future one.
        let dict = validTXT(version: "99")
        #expect(BonjourBrowser.discoveredHost(txtDictionary: dict, endpoint: testEndpoint) == nil)
    }

    @Test func aSupportedVersionAmongOthersIsAccepted() {
        let dict = validTXT(version: "1,2,99")
        #expect(BonjourBrowser.discoveredHost(txtDictionary: dict, endpoint: testEndpoint) != nil)
    }

    @Test func malformedRecordIsHidden() {
        var dict = validTXT()
        dict.removeValue(forKey: "id") // required field missing entirely
        #expect(BonjourBrowser.discoveredHost(txtDictionary: dict, endpoint: testEndpoint) == nil)
    }

    @Test func discoveredHostEqualityIgnoresEndpointIdentity() {
        let a = BonjourBrowser.discoveredHost(txtDictionary: validTXT(), endpoint: testEndpoint)
        let b = BonjourBrowser.discoveredHost(txtDictionary: validTXT(), endpoint: .hostPort(host: "10.0.0.9", port: 12345))
        // `DiscoveredHost.==` compares id/name/ports only (spec §3.1.2's `id` is the stable match
        // key; the endpoint may legitimately differ browse-to-browse as a Mac's IP changes).
        #expect(a == b)
    }

    @Test func transportErrorCasesAreDistinctAndEquatable() {
        #expect(TransportError.localNetworkDenied == TransportError.localNetworkDenied)
        #expect(TransportError.localNetworkDenied != TransportError.timedOut)
        #expect(TransportError.invalidPort(70000) == TransportError.invalidPort(70000))
        #expect(TransportError.invalidPort(1) != TransportError.invalidPort(2))
    }
}
