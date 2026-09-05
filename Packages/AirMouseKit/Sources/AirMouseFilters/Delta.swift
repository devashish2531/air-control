import Foundation

/// A pointer/scroll delta in points, with saturation helpers mirroring the wire's fixed-point
/// format (spec §3.5.2 offsets 8/10/12/14: `i16 LE, 1/8 point`, range ±4095.875 pt per datagram).
public struct Delta: Sendable, Equatable, Codable {
    public var dx: Double
    public var dy: Double

    public init(dx: Double, dy: Double) {
        self.dx = dx
        self.dy = dy
    }

    public static let zero = Delta(dx: 0, dy: 0)

    public var length: Double {
        (dx * dx + dy * dy).squareRoot()
    }

    public var vector: Vector2 { Vector2(x: dx, y: dy) }

    public init(_ v: Vector2) {
        self.dx = v.x
        self.dy = v.y
    }

    public static func + (lhs: Delta, rhs: Delta) -> Delta {
        Delta(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy)
    }

    public static func * (lhs: Delta, rhs: Double) -> Delta {
        Delta(dx: lhs.dx * rhs, dy: lhs.dy * rhs)
    }

    /// Largest and smallest point value representable in the wire's i16-eighth-point field.
    public static let eighthPointMax: Double = Double(Int16.max) / 8.0   // 4095.875
    public static let eighthPointMin: Double = Double(Int16.min) / 8.0   // -4096.0

    /// Quantizes one axis value (in points) to the wire's i16 eighth-point fixed format, saturating
    /// (never wrapping) at the representable range.
    public static func quantizeEighthPoint(_ pointValue: Double) -> Int16 {
        guard pointValue.isFinite else { return 0 }
        let scaled = (pointValue * 8.0).rounded()
        let clamped = Swift.min(Swift.max(scaled, Double(Int16.min)), Double(Int16.max))
        return Int16(clamped)
    }

    /// This delta converted to the wire's i16 eighth-point pair, saturating each axis independently.
    public var eighthPoints: (x: Int16, y: Int16) {
        (Delta.quantizeEighthPoint(dx), Delta.quantizeEighthPoint(dy))
    }

    /// Reconstructs a point delta from the wire's i16 eighth-point pair.
    public static func fromEighthPoints(x: Int16, y: Int16) -> Delta {
        Delta(dx: Double(x) / 8.0, dy: Double(y) / 8.0)
    }
}
