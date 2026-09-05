import Foundation
import Testing
@testable import AirMouseProtocol

@Suite struct PairingURLTests {
    static func makeValid(
        addresses: [String] = ["172.20.10.5", "192.168.1.42"]
    ) throws -> PairingURL {
        try PairingURL(
            version: 1,
            hostID: Data(repeating: 0x01, count: 16),
            hostName: "Devashish's Mac mini",
            addresses: addresses,
            tcpPort: 47_800,
            fingerprint: Data(repeating: 0x02, count: 32),
            secret: Data(repeating: 0x03, count: 16)
        )
    }

    @Test func formatThenParseRoundTrips() throws {
        let original = try Self.makeValid()
        let string = try original.formatted()
        let parsed = try PairingURL.parse(string)
        #expect(parsed == original)
    }

    @Test func udpPortDefaultsToTcpPortWhenOmitted() throws {
        let url = try Self.makeValid()
        #expect(url.udpPort == url.tcpPort)
        let string = try url.formatted()
        #expect(string.contains("u=\(url.tcpPort)"))
    }

    @Test func explicitUdpPortDiffersFromTcpPort() throws {
        let url = try PairingURL(
            version: 1,
            hostID: Data(repeating: 0x01, count: 16),
            hostName: "Mac",
            addresses: ["10.0.0.5"],
            tcpPort: 47_800,
            udpPort: 47_801,
            fingerprint: Data(repeating: 0x02, count: 32),
            secret: Data(repeating: 0x03, count: 16)
        )
        let parsed = try PairingURL.parse(try url.formatted())
        #expect(parsed.udpPort == 47_801)
    }

    @Test func parsedURLHasAirmouseSchemeAndPairHost() throws {
        let url = try Self.makeValid()
        let string = try url.formatted()
        #expect(string.hasPrefix("airmouse://pair?"))
    }

    @Test func acceptsIPv6Addresses() throws {
        let url = try Self.makeValid(addresses: ["fe80::1", "2001:db8::1"])
        let parsed = try PairingURL.parse(try url.formatted())
        #expect(parsed.addresses == url.addresses)
    }

    @Test func rejectsMoreThanSixAddresses() {
        let tooMany = (0..<7).map { "10.0.0.\($0)" }
        #expect(throws: ProtocolError.self) {
            _ = try Self.makeValid(addresses: tooMany)
        }
    }

    @Test func rejectsEmptyAddressList() {
        #expect(throws: ProtocolError.self) {
            _ = try Self.makeValid(addresses: [])
        }
    }

    @Test func rejectsMalformedAddress() {
        #expect(throws: ProtocolError.self) {
            _ = try Self.makeValid(addresses: ["not-an-ip"])
        }
    }

    @Test func rejectsWrongHostIDLength() {
        #expect(throws: ProtocolError.self) {
            _ = try PairingURL(
                version: 1,
                hostID: Data(repeating: 0x01, count: 15),
                hostName: "Mac",
                addresses: ["10.0.0.1"],
                tcpPort: 47_800,
                fingerprint: Data(repeating: 0x02, count: 32),
                secret: Data(repeating: 0x03, count: 16)
            )
        }
    }

    @Test func rejectsWrongFingerprintLength() {
        #expect(throws: ProtocolError.self) {
            _ = try PairingURL(
                version: 1,
                hostID: Data(repeating: 0x01, count: 16),
                hostName: "Mac",
                addresses: ["10.0.0.1"],
                tcpPort: 47_800,
                fingerprint: Data(repeating: 0x02, count: 16), // should be 32
                secret: Data(repeating: 0x03, count: 16)
            )
        }
    }

    @Test func rejectsWrongSecretLength() {
        #expect(throws: ProtocolError.self) {
            _ = try PairingURL(
                version: 1,
                hostID: Data(repeating: 0x01, count: 16),
                hostName: "Mac",
                addresses: ["10.0.0.1"],
                tcpPort: 47_800,
                fingerprint: Data(repeating: 0x02, count: 32),
                secret: Data(repeating: 0x03, count: 8) // should be 16
            )
        }
    }

    @Test func rejectsHostNameOver63Bytes() {
        let longName = String(repeating: "a", count: 64)
        #expect(throws: ProtocolError.self) {
            _ = try PairingURL(
                version: 1,
                hostID: Data(repeating: 0x01, count: 16),
                hostName: longName,
                addresses: ["10.0.0.1"],
                tcpPort: 47_800,
                fingerprint: Data(repeating: 0x02, count: 32),
                secret: Data(repeating: 0x03, count: 16)
            )
        }
    }

    @Test func parseRejectsWrongScheme() {
        #expect(throws: ProtocolError.self) {
            _ = try PairingURL.parse("http://pair?v=1")
        }
    }

    @Test func parseRejectsMissingRequiredParam() throws {
        let url = try Self.makeValid()
        let full = try url.formatted()
        let withoutSecret = full.replacingOccurrences(of: "&s=", with: "&x=")
        #expect(throws: ProtocolError.self) {
            _ = try PairingURL.parse(withoutSecret)
        }
    }

    @Test func parseRejectsGarbageInput() {
        #expect(throws: ProtocolError.self) {
            _ = try PairingURL.parse("not a url at all \u{0}")
        }
    }

    @Test func parseRejectsMalformedB64uField() throws {
        let url = try Self.makeValid()
        var full = try url.formatted()
        full = full.replacingOccurrences(of: url.secret.b64u, with: "not-valid-b64u-!!!")
        #expect(throws: ProtocolError.self) {
            _ = try PairingURL.parse(full)
        }
    }

    @Test func truncatingToFitDropsAddressesNotSecret() throws {
        // A long host name plus many addresses to force truncation.
        let manyAddresses = (0..<6).map { "192.168.100.\($0)" }
        let longName = String(repeating: "x", count: 60)
        let secret = Data(repeating: 0xAB, count: 16)
        let url = try PairingURL.truncatingToFit(
            version: 1,
            hostID: Data(repeating: 0x01, count: 16),
            hostName: longName,
            addresses: manyAddresses,
            tcpPort: 47_800,
            fingerprint: Data(repeating: 0x02, count: 32),
            secret: secret
        )
        #expect(url.secret == secret)
        #expect(url.addresses.count <= manyAddresses.count)
        let formatted = try url.formatted()
        #expect(formatted.utf8.count <= PairingURL.maxURLLength)
    }

    @Test func totalURLLengthStaysWithinSpecLimit() throws {
        let url = try Self.makeValid(addresses: ["172.20.10.5", "192.168.1.42", "fe80::1234:5678:9abc:def0"])
        let formatted = try url.formatted()
        #expect(formatted.utf8.count <= PairingURL.maxURLLength)
    }

    @Test func isSupportedVersionChecksMembership() throws {
        let url = try Self.makeValid()
        #expect(url.isSupportedVersion(in: [1, 2]))
        #expect(!url.isSupportedVersion(in: [2, 3]))
    }

    @Test func ipLiteralValidatorAcceptsAndRejectsExpectedForms() {
        #expect(IPLiteral.isValidIPv4("192.168.1.1"))
        #expect(IPLiteral.isValidIPv4("0.0.0.0"))
        #expect(!IPLiteral.isValidIPv4("256.1.1.1"))
        #expect(!IPLiteral.isValidIPv4("1.2.3"))
        #expect(!IPLiteral.isValidIPv4("01.2.3.4"))

        #expect(IPLiteral.isValidIPv6("::1"))
        #expect(IPLiteral.isValidIPv6("2001:db8::1"))
        #expect(IPLiteral.isValidIPv6("fe80::1234:5678:9abc:def0"))
        #expect(!IPLiteral.isValidIPv6("[::1]"))
        #expect(!IPLiteral.isValidIPv6("fe80::1%en0"))
    }
}
