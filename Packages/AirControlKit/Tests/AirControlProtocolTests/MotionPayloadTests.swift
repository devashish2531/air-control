import Foundation
import Testing
@testable import AirControlProtocol

/// Byte-exact encode/decode of `MotionPayload` (spec §3.5.2) against hand-computed hex vectors in
/// `Vectors/motion.json` (format documented in that file's `_format` key).
@Suite struct MotionPayloadTests {
    struct Vector: Decodable {
        var name: String
        var hex: String
        var flags: UInt8
        var source: UInt8
        var samples: UInt8
        var timestamp: UInt32
        var dx: Int16
        var dy: Int16
        var scrollX: Int16
        var scrollY: Int16
    }

    struct VectorFile: Decodable {
        var vectors: [Vector]
    }

    static let vectors: [Vector] = {
        let url = Bundle.module.url(forResource: "motion", withExtension: "json", subdirectory: "Vectors")!
        let data = try! Data(contentsOf: url)
        return try! JSONDecoder().decode(VectorFile.self, from: data).vectors
    }()

    static func bytes(fromHex hex: String) -> Data {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            data.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return data
    }

    @Test func vectorFileIsNonEmpty() {
        #expect(!Self.vectors.isEmpty)
    }

    @Test(arguments: vectors)
    func decodesHexVectorExactly(vector: Vector) throws {
        let data = Self.bytes(fromHex: vector.hex)
        #expect(data.count == MotionPayload.byteCount)

        let payload = try #require(MotionPayload(data: data))
        #expect(payload.flags.rawValue == vector.flags)
        #expect(payload.source.rawValue == vector.source)
        #expect(payload.samples == vector.samples)
        #expect(payload.timestamp == vector.timestamp)
        #expect(payload.dx == vector.dx)
        #expect(payload.dy == vector.dy)
        #expect(payload.scrollX == vector.scrollX)
        #expect(payload.scrollY == vector.scrollY)
    }

    @Test(arguments: vectors)
    func reEncodingProducesCanonicalBytes(vector: Vector) throws {
        // Re-encoding must always emit reserved byte 3 == 0, even for the vector whose *input*
        // bytes have it nonzero (spec §3.7: "ignored when received").
        let data = Self.bytes(fromHex: vector.hex)
        let payload = try #require(MotionPayload(data: data))
        let reEncoded = payload.encoded()

        var expected = data
        expected[expected.index(expected.startIndex, offsetBy: 3)] = 0
        #expect(reEncoded == expected)
    }

    @Test func encodeIntoUnsafeBufferMatchesEncodedData() {
        let payload = MotionPayload(flags: [.scrollBegan, .predicted], source: .touch, samples: 3, timestamp: 999, dx: 10, dy: -20, scrollX: 30, scrollY: -40)
        var buffer = [UInt8](repeating: 0xFF, count: MotionPayload.byteCount)
        buffer.withUnsafeMutableBytes { payload.encode(into: $0) }
        #expect(Data(buffer) == payload.encoded())
    }

    @Test func initFailsForShortData() {
        #expect(MotionPayload(data: Data(count: 15)) == nil)
    }

    @Test func initFailsForLongData() {
        #expect(MotionPayload(data: Data(count: 17)) == nil)
    }

    @Test func initFailsForUnknownSource() {
        var bytes = [UInt8](repeating: 0, count: MotionPayload.byteCount)
        bytes[1] = 42 // not a recognized MotionSource
        #expect(MotionPayload(data: Data(bytes)) == nil)
    }

    @Test func pointsConvenienceInitializerRoundTripsThroughFixedPoint() {
        let payload = MotionPayload(
            source: .touch,
            samples: 1,
            timestamp: 0,
            dxPoints: 12.25,
            dyPoints: -8.125,
            scrollXPoints: 0,
            scrollYPoints: 100.5
        )
        #expect(payload.dxPoints == 12.25)
        #expect(payload.dyPoints == -8.125)
        #expect(payload.scrollYPoints == 100.5)
    }

    @Test func flagsAreAnOptionSet() {
        var flags: MotionFlags = [.scrollBegan, .motionEnd]
        #expect(flags.contains(.scrollBegan))
        #expect(!flags.contains(.probe))
        flags.insert(.probe)
        #expect(flags.rawValue == 0b0001_0101)
    }

    @Test func motionSourceRawValuesMatchSpec() {
        #expect(MotionSource.touch.rawValue == 0)
        #expect(MotionSource.gyro.rawValue == 1)
        #expect(MotionSource.externalPointer.rawValue == 2)
        #expect(MotionSource.tcpFallback.rawValue == 3)
        #expect(MotionSource.probe.rawValue == 255)
    }
}
