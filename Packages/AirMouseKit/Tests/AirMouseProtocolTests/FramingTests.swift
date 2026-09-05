import Foundation
import Testing
@testable import AirMouseProtocol

/// Control-channel framing (spec §3.4.1): `u32 LE length ‖ u8 kind ‖ body`.
@Suite struct FramingTests {
    @Test func encodeThenDecodeRoundTrips() throws {
        let body = Data("hello".utf8)
        let framed = try FrameEncoder.encode(kind: .json, body: body)
        #expect(framed.count == 4 + 1 + body.count)

        var decoder = FrameDecoder()
        let frames = try decoder.feed(framed)
        #expect(frames.count == 1)
        #expect(frames[0].kind == .json)
        #expect(frames[0].body == body)
        #expect(decoder.pendingByteCount == 0)
    }

    @Test func lengthPrefixIsLittleEndian() throws {
        let body = Data(repeating: 0x41, count: 10)
        let framed = try FrameEncoder.encode(kind: .json, body: body)
        // length = 1 (kind) + 10 (body) = 11 = 0x0000000B
        #expect(Array(framed.prefix(4)) == [0x0B, 0x00, 0x00, 0x00])
    }

    @Test func emptyBodyIsLegal() throws {
        let framed = try FrameEncoder.encode(kind: .json, body: Data())
        var decoder = FrameDecoder()
        let frames = try decoder.feed(framed)
        #expect(frames.count == 1)
        #expect(frames[0].body.isEmpty)
    }

    @Test func decodesAcrossSplitChunks() throws {
        let body = Data("split across many tiny reads".utf8)
        let framed = try FrameEncoder.encode(kind: .json, body: body)

        var decoder = FrameDecoder()
        var collected: [Frame] = []
        for byte in framed {
            collected += try decoder.feed(Data([byte]))
        }
        #expect(collected.count == 1)
        #expect(collected[0].body == body)
    }

    @Test func decodesMultipleFramesMergedInOneChunk() throws {
        let bodies = [Data("one".utf8), Data("two".utf8), Data("three".utf8)]
        var merged = Data()
        for body in bodies {
            merged.append(try FrameEncoder.encode(kind: .json, body: body))
        }

        var decoder = FrameDecoder()
        let frames = try decoder.feed(merged)
        #expect(frames.count == bodies.count)
        #expect(frames.map(\.body) == bodies)
    }

    @Test func retainsPartialTrailingFrameAcrossFeeds() throws {
        let first = Data("first".utf8)
        let second = Data("second".utf8)
        let framedFirst = try FrameEncoder.encode(kind: .json, body: first)
        let framedSecond = try FrameEncoder.encode(kind: .json, body: second)
        let combined = framedFirst + framedSecond

        var decoder = FrameDecoder()
        // Feed everything except the last 3 bytes of the second frame.
        let splitPoint = combined.count - 3
        let firstChunk = combined.prefix(splitPoint)
        let secondChunk = combined.suffix(3)

        let framesFromFirstChunk = try decoder.feed(Data(firstChunk))
        #expect(framesFromFirstChunk == [Frame(kind: .json, body: first)])
        #expect(decoder.pendingByteCount > 0)

        let framesFromSecondChunk = try decoder.feed(Data(secondChunk))
        #expect(framesFromSecondChunk == [Frame(kind: .json, body: second)])
        #expect(decoder.pendingByteCount == 0)
    }

    @Test func motionBatchFrameRoundTrips() throws {
        let body = try FrameEncoder.encode(kind: .motionBatch, body: Data(repeating: 0x99, count: 32))
        var decoder = FrameDecoder()
        let frames = try decoder.feed(body)
        #expect(frames.count == 1)
        #expect(frames[0].kind == .motionBatch)
    }

    @Test func encodeThrowsOnOversizedBody() {
        let oversized = Data(count: ProtocolConstants.maxControlFrameBodyBytes + 1)
        #expect(throws: ProtocolError.self) {
            _ = try FrameEncoder.encode(kind: .json, body: oversized)
        }
    }

    @Test func exactlyMaxBodySizeIsAccepted() throws {
        let body = Data(count: ProtocolConstants.maxControlFrameBodyBytes)
        let framed = try FrameEncoder.encode(kind: .json, body: body)
        var decoder = FrameDecoder()
        let frames = try decoder.feed(framed)
        #expect(frames.count == 1)
        #expect(frames[0].body.count == ProtocolConstants.maxControlFrameBodyBytes)
    }

    @Test func decoderThrowsFrameTooLargeForOversizedDeclaredLength() throws {
        var header = Data()
        let bogusLength = ProtocolConstants.maxFrameLengthFieldValue + 1
        header.append(contentsOf: bogusLength.littleEndianBytes)
        header.append(FrameKind.json.rawValue)

        var decoder = FrameDecoder()
        #expect(throws: ProtocolError.self) {
            _ = try decoder.feed(header)
        }
    }

    @Test func decoderThrowsBadFrameForUnknownKind() throws {
        var header = Data()
        header.append(contentsOf: UInt32(2).littleEndianBytes) // length = 1 (kind) + 1 (body byte)
        header.append(0xEE) // unrecognized kind
        header.append(0x00) // one body byte

        var decoder = FrameDecoder()
        #expect(throws: ProtocolError.self) {
            _ = try decoder.feed(header)
        }
    }

    @Test func decoderThrowsBadFrameForZeroLength() throws {
        var header = Data()
        header.append(contentsOf: UInt32(0).littleEndianBytes)

        var decoder = FrameDecoder()
        #expect(throws: ProtocolError.self) {
            _ = try decoder.feed(header)
        }
    }

    @Test func decoderIgnoresGarbageUntilEnoughBytesArrive() throws {
        // Three bytes is not enough to even read the length prefix; feeding them must not throw
        // and must simply be retained.
        var decoder = FrameDecoder()
        let frames = try decoder.feed(Data([0xFF, 0xFF, 0xFF]))
        #expect(frames.isEmpty)
        #expect(decoder.pendingByteCount == 3)
    }
}
