import Foundation

/// Helpers for the wire's client timestamp field (spec §3.5.2 offset 4): `u32 LE, client monotonic
/// clock in µs (wraps every 71.6 min; receiver uses modular arithmetic)`.
///
/// This type only does the encode/decode/elapsed-time arithmetic; it is not itself the wire codec
/// (that lives in `AirMouseProtocol`, which this module does not depend on).
public enum TimestampMicros {
    /// One past the largest representable value, i.e. the wraparound modulus.
    public static let modulus: Double = 4_294_967_296.0 // 2^32

    /// Wall/monotonic period of one wraparound, in seconds (~71.58 min, matches spec prose "71.6 min").
    public static let wrapPeriod: TimeInterval = modulus / 1_000_000.0

    /// Encodes a `TimeInterval` (seconds, arbitrary origin) into the wire's wrapping `UInt32` of
    /// microseconds.
    public static func encode(_ seconds: TimeInterval) -> UInt32 {
        let micros = seconds * 1_000_000.0
        var wrapped = micros.truncatingRemainder(dividingBy: modulus)
        if wrapped < 0 { wrapped += modulus }
        // `wrapped` is in [0, modulus); round to nearest integer before the UInt32 cast so values
        // just under the modulus (from floating point error) don't overflow.
        let rounded = wrapped.rounded()
        return rounded >= modulus ? 0 : UInt32(rounded)
    }

    /// Naively interprets a raw wire value as seconds since the same arbitrary origin as `encode`,
    /// ignoring wraparound. Only meaningful for values known not to have wrapped.
    public static func seconds(_ micros: UInt32) -> TimeInterval {
        TimeInterval(micros) / 1_000_000.0
    }

    /// Signed elapsed time from `from` to `to`, correct across a single wraparound using modular
    /// arithmetic (spec §3.5.2: "receiver uses modular arithmetic"). Valid as long as the true
    /// elapsed time is less than half the wrap period (~35.8 min) in magnitude, which always holds
    /// for consecutive motion datagrams.
    public static func elapsedSeconds(from: UInt32, to: UInt32) -> TimeInterval {
        let wrappingDiff = to &- from // UInt32 wrapping subtraction
        let signedMicros = Int64(Int32(bitPattern: wrappingDiff))
        return TimeInterval(signedMicros) / 1_000_000.0
    }
}
