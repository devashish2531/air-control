import Foundation
import Testing
@testable import AirMouseProtocol

@Suite struct LittleEndianCodingTests {
    @Test func uint16RoundTrips() {
        for value: UInt16 in [0, 1, 255, 256, 0xABCD, .max] {
            let bytes = value.littleEndianBytes
            #expect(bytes.count == 2)
            #expect(UInt16(littleEndianBytes: bytes) == value)
        }
    }

    @Test func uint32RoundTrips() {
        for value: UInt32 in [0, 1, 0x0000_00FF, 0xDEAD_BEEF, .max] {
            let bytes = value.littleEndianBytes
            #expect(bytes.count == 4)
            #expect(UInt32(littleEndianBytes: bytes) == value)
        }
    }

    @Test func uint64RoundTrips() {
        for value: UInt64 in [0, 1, 0xFFFF_FFFF, 0x0123_4567_89AB_CDEF, .max] {
            let bytes = value.littleEndianBytes
            #expect(bytes.count == 8)
            #expect(UInt64(littleEndianBytes: bytes) == value)
        }
    }

    @Test func byteOrderIsLittleEndianNotBigEndian() {
        // spec §3.0: "Byte order | Little-endian for every integer on both channels".
        let value: UInt32 = 0x0102_0304
        #expect(value.littleEndianBytes == [0x04, 0x03, 0x02, 0x01])
    }

    @Test func initFailsForWrongByteCount() {
        #expect(UInt32(littleEndianBytes: [0x01, 0x02, 0x03]) == nil)
        #expect(UInt32(littleEndianBytes: [0x01, 0x02, 0x03, 0x04, 0x05]) == nil)
    }

    @Test func int16RoundTripsIncludingNegatives() {
        for value: Int16 in [Int16.min, -1, 0, 1, Int16.max] {
            let bytes = value.littleEndianBytes
            #expect(Int16(littleEndianBytes: bytes) == value)
        }
    }
}
