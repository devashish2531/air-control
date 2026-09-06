import Foundation
import Testing
@testable import AirControlProtocol

@Suite struct TXTRecordTests {
    static func makeValid() throws -> TXTRecord {
        try TXTRecord(
            supportedVersions: [1],
            hostName: "Devashish's Mac mini",
            hostID: Data(repeating: 0x01, count: 16),
            fingerprintPrefix: Data(repeating: 0x02, count: 16),
            machineModel: "Mac15,6",
            tcpPort: 47_800,
            udpPort: 47_800
        )
    }

    @Test func serializeThenParseRoundTrips() throws {
        let record = try Self.makeValid()
        let parsed = try TXTRecord(parsing: record.serialize())
        #expect(parsed == record)
    }

    @Test func serializedDictionaryHasExactSpecKeys() throws {
        let dict = try Self.makeValid().serialize()
        #expect(Set(dict.keys) == ["v", "n", "id", "fp", "m", "tp", "up"])
    }

    @Test func supportsVersionChecksMembership() throws {
        let record = try TXTRecord(
            supportedVersions: [1, 2],
            hostName: "Mac",
            hostID: Data(repeating: 0x01, count: 16),
            fingerprintPrefix: Data(repeating: 0x02, count: 16),
            machineModel: "Mac15,6",
            tcpPort: 47_800,
            udpPort: 47_800
        )
        #expect(record.supportsVersion(1))
        #expect(record.supportsVersion(2))
        #expect(!record.supportsVersion(3))
    }

    @Test func parsingRejectsMissingV() {
        var dict = try! Self.makeValid().serialize()
        dict.removeValue(forKey: "v")
        #expect(throws: ProtocolError.self) {
            _ = try TXTRecord(parsing: dict)
        }
    }

    @Test func parsingRejectsNonAscendingVersions() {
        var dict = try! Self.makeValid().serialize()
        dict["v"] = "2,1"
        #expect(throws: ProtocolError.self) {
            _ = try TXTRecord(parsing: dict)
        }
    }

    @Test func parsingRejectsGarbageVersionList() {
        var dict = try! Self.makeValid().serialize()
        dict["v"] = "one,two"
        #expect(throws: ProtocolError.self) {
            _ = try TXTRecord(parsing: dict)
        }
    }

    @Test func parsingRejectsWrongLengthHostID() {
        var dict = try! Self.makeValid().serialize()
        dict["id"] = Data(repeating: 0x01, count: 8).b64u
        #expect(throws: ProtocolError.self) {
            _ = try TXTRecord(parsing: dict)
        }
    }

    @Test func parsingRejectsMalformedB64u() {
        var dict = try! Self.makeValid().serialize()
        dict["fp"] = "not valid b64u!!"
        #expect(throws: ProtocolError.self) {
            _ = try TXTRecord(parsing: dict)
        }
    }

    @Test func parsingRejectsMissingPort() {
        var dict = try! Self.makeValid().serialize()
        dict.removeValue(forKey: "tp")
        #expect(throws: ProtocolError.self) {
            _ = try TXTRecord(parsing: dict)
        }
    }

    @Test func constructorRejectsHostNameOver63Bytes() {
        #expect(throws: ProtocolError.self) {
            _ = try TXTRecord(
                supportedVersions: [1],
                hostName: String(repeating: "a", count: 64),
                hostID: Data(repeating: 0x01, count: 16),
                fingerprintPrefix: Data(repeating: 0x02, count: 16),
                machineModel: "Mac15,6",
                tcpPort: 47_800,
                udpPort: 47_800
            )
        }
    }

    @Test func constructorRejectsWrongFingerprintPrefixLength() {
        #expect(throws: ProtocolError.self) {
            _ = try TXTRecord(
                supportedVersions: [1],
                hostName: "Mac",
                hostID: Data(repeating: 0x01, count: 16),
                fingerprintPrefix: Data(repeating: 0x02, count: 32), // must be 16 (a prefix)
                machineModel: "Mac15,6",
                tcpPort: 47_800,
                udpPort: 47_800
            )
        }
    }

    @Test func totalSizeStaysWithin400Bytes() throws {
        let record = try Self.makeValid()
        let dict = record.serialize()
        let total = dict.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
        #expect(total <= 400)
    }
}
