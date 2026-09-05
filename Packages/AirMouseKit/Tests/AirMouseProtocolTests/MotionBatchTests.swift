import Foundation
import Testing
@testable import AirMouseProtocol

/// `kind = 0x02` TCP motion fallback batch frames (spec §3.4.1, §3.5.9): 1–16 concatenated
/// 16-byte motion payloads, no AEAD, no counter.
@Suite struct MotionBatchTests {
    static func samplePayload(_ seed: UInt8) -> MotionPayload {
        MotionPayload(source: .touch, samples: 1, timestamp: UInt32(seed), dx: Int16(seed), dy: 0, scrollX: 0, scrollY: 0)
    }

    @Test func encodeThenDecodeRoundTripsForOnePayload() throws {
        let payloads = [Self.samplePayload(1)]
        let body = try MotionBatch.encode(payloads)
        #expect(body.count == MotionPayload.byteCount)
        let decoded = try MotionBatch.decode(body)
        #expect(decoded == payloads)
    }

    @Test func encodeThenDecodeRoundTripsForSixteenPayloads() throws {
        let payloads = (0..<16).map { Self.samplePayload(UInt8($0)) }
        let body = try MotionBatch.encode(payloads)
        #expect(body.count == 16 * MotionPayload.byteCount)
        let decoded = try MotionBatch.decode(body)
        #expect(decoded == payloads)
    }

    @Test func encodeThrowsForEmptyArray() {
        #expect(throws: ProtocolError.self) {
            _ = try MotionBatch.encode([])
        }
    }

    @Test func encodeThrowsForSeventeenPayloads() {
        let payloads = (0..<17).map { Self.samplePayload(UInt8($0)) }
        #expect(throws: ProtocolError.self) {
            _ = try MotionBatch.encode(payloads)
        }
    }

    @Test func decodeThrowsForBodyNotAMultipleOfSixteen() {
        #expect(throws: ProtocolError.self) {
            _ = try MotionBatch.decode(Data(count: 17))
        }
    }

    @Test func decodeThrowsForEmptyBody() {
        #expect(throws: ProtocolError.self) {
            _ = try MotionBatch.decode(Data())
        }
    }

    @Test func decodeThrowsForMoreThanSixteenPayloads() {
        let body = Data(count: 17 * MotionPayload.byteCount)
        #expect(throws: ProtocolError.self) {
            _ = try MotionBatch.decode(body)
        }
    }

    @Test func decodeThrowsForUnrecognizedSourceInsideBatch() {
        var bytes = [UInt8](repeating: 0, count: MotionPayload.byteCount)
        bytes[1] = 42 // unrecognized source
        #expect(throws: ProtocolError.self) {
            _ = try MotionBatch.decode(Data(bytes))
        }
    }

    @Test func datagramLayoutConstantsMatchSpecSizes() {
        #expect(MotionDatagramLayout.totalSize == ProtocolConstants.udpDatagramSize)
        #expect(MotionDatagramLayout.sessionIDSize == 4)
        #expect(MotionDatagramLayout.counterSize == 8)
        #expect(MotionDatagramLayout.ciphertextSize == MotionPayload.byteCount)
        #expect(MotionDatagramLayout.tagSize == 16)
        #expect(MotionDatagramLayout.additionalAuthenticatedDataRange == 0..<12)
    }
}
