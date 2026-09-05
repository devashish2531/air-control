import Foundation

/// Bit flags in byte 0 of the motion payload. spec §3.5.2:
/// "flags | bit0 scrollBegan · bit1 scrollEnded · bit2 motionEnd · bit3 predicted · bit4 probe ·
/// bit5 echo · bits6–7 reserved (0)". spec §3.7: "spare `flags` bits must be zero when sent and
/// ignored when received."
public struct MotionFlags: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// bit0: first scroll datagram of a new scroll gesture (spec §3.6.2 `began`).
    public static let scrollBegan = MotionFlags(rawValue: 1 << 0)
    /// bit1: last scroll datagram of a gesture (spec §3.6.2 `ended`).
    public static let scrollEnded = MotionFlags(rawValue: 1 << 1)
    /// bit2: finger lifted / clutch released (spec §3.5.6).
    public static let motionEnd = MotionFlags(rawValue: 1 << 2)
    /// bit3: this datagram's deltas are host-side extrapolated, not measured (spec §3.5.6).
    public static let predicted = MotionFlags(rawValue: 1 << 3)
    /// bit4: this is a latency probe datagram, not real motion (spec §3.5.8).
    public static let probe = MotionFlags(rawValue: 1 << 4)
    /// bit5: this is the host's reflected echo of a probe (spec §3.5.8).
    public static let echo = MotionFlags(rawValue: 1 << 5)

    /// Bits 6–7, which the spec reserves and requires to be zero on send.
    public static let reservedMask: UInt8 = 0b1100_0000
}
