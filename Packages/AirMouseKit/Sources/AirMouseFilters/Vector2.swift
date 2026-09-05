import simd

/// A 2D double-precision vector used throughout the module for points, deltas and velocities.
/// Backed by `SIMD2<Double>` (per the module's "Foundation, simd only" import rule) but exposed as
/// its own named type so call sites read as pointer/motion math rather than raw SIMD.
public struct Vector2: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(_ v: SIMD2<Double>) {
        self.x = v.x
        self.y = v.y
    }

    public static let zero = Vector2(x: 0, y: 0)

    public var simd: SIMD2<Double> { SIMD2(x, y) }

    public var length: Double {
        (x * x + y * y).squareRoot()
    }

    public static func + (lhs: Vector2, rhs: Vector2) -> Vector2 {
        Vector2(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func - (lhs: Vector2, rhs: Vector2) -> Vector2 {
        Vector2(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public static func * (lhs: Vector2, rhs: Double) -> Vector2 {
        Vector2(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    public static func * (lhs: Double, rhs: Vector2) -> Vector2 {
        rhs * lhs
    }

    public static prefix func - (v: Vector2) -> Vector2 {
        Vector2(x: -v.x, y: -v.y)
    }

    public static func += (lhs: inout Vector2, rhs: Vector2) {
        lhs = lhs + rhs
    }
}

/// A point in the same 2D space as `Vector2` (screen/display coordinates, points not pixels unless
/// noted). Kept as a separate name for readability at call sites (`DisplayClamp`, `GestureRecognizer`)
/// even though the representation is identical.
public typealias Point = Vector2
