import Foundation

/// Little-endian byte (de)serialization for fixed-width integers. spec §3.0: "Byte order |
/// Little-endian for every integer on both channels, including the TCP length prefix". spec §6.2
/// (architecture): "`UInt32/UInt64.littleEndianBytes`". Implemented with plain shifts rather than
/// `withUnsafeBytes` so it works for any `FixedWidthInteger` without alignment assumptions; the
/// one place this module uses raw pointers on a hot path is `MotionPayload`.
public extension FixedWidthInteger {
    /// This integer's bytes in little-endian order, least-significant byte first.
    var littleEndianBytes: [UInt8] {
        (0..<MemoryLayout<Self>.size).map { UInt8(truncatingIfNeeded: self >> (8 * $0)) }
    }

    /// Reconstructs an integer from exactly `MemoryLayout<Self>.size` little-endian bytes.
    /// Returns `nil` (rather than trapping) if `bytes` is not exactly that length, so callers
    /// decoding untrusted wire data can handle malformed input gracefully.
    init?(littleEndianBytes bytes: some Collection<UInt8>) {
        guard bytes.count == MemoryLayout<Self>.size else { return nil }
        var value: Self = 0
        for (index, byte) in bytes.enumerated() {
            value |= Self(byte) << (8 * index)
        }
        self = value
    }
}
