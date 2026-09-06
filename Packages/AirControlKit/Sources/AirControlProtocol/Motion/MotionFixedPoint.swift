import Foundation

/// Conversion between `Double` points and the motion payload's fixed-point 1/8-point `Int16`
/// deltas. spec §3.5.2: "dx | i16 LE, pointer delta X in 1/8 point (±4095.875 pt per datagram)".
/// spec decision (§3.5.2): "Fixed-point i16 instead of f32 keeps the payload at 16 bytes ...
/// 1/8 pt resolution is below the host's sub-pixel accumulator granularity."
public enum MotionFixedPoint {
    /// Eighths-of-a-point scale factor: `encoded = round(points * scale)`.
    public static let scale: Double = 8.0

    /// The largest magnitude representable without saturation, `4095.875` pt (spec §3.5.2).
    public static let maxMagnitudePoints: Double = Double(Int16.max) / scale

    /// Converts a delta in points to its 1/8-point fixed-point representation, saturating to
    /// `Int16.min...Int16.max` rather than wrapping if the magnitude exceeds what one datagram
    /// can carry.
    public static func encode(_ points: Double) -> Int16 {
        guard points.isFinite else { return 0 }
        let scaled = (points * scale).rounded()
        let clamped = Swift.min(Double(Int16.max), Swift.max(Double(Int16.min), scaled))
        return Int16(clamped)
    }

    /// Converts a 1/8-point fixed-point delta back to points.
    public static func decode(_ eighths: Int16) -> Double {
        Double(eighths) / scale
    }
}
