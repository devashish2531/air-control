import Foundation

/// Host-side pointer acceleration curve (spec §5.4), applied to touch and external-pointer deltas —
/// **never** to gyro deltas ("accel = 1 for source == gyro"; gyro's own gain lives in `GyroMapper`
/// and already stands in for an acceleration curve since the user's arm supplies it).
///
/// ```
/// base(s)  = 0.6 · (4.0 / 0.6)^((s − 1) / 9)     s ∈ 1…10  → 0.60 … 4.00
/// accel(v) = 1 + a · min(v / v_ref, 1)²           v_ref = 1500 pt/s
/// gain     = base(s) · accel(v)
/// ```
public struct AccelerationCurve: Sendable {
    /// Acceleration strength `a` (spec §5.4 / §11.3): off/precise/default/fast.
    public enum Profile: Sendable, Equatable, CaseIterable {
        case off
        case precise
        case `default`
        case fast

        public var a: Double {
            switch self {
            case .off: return 0
            case .precise: return 1.0
            case .default: return 2.5
            case .fast: return 4.0
            }
        }
    }

    /// Pointer sensitivity slider, 1...10 (spec default 5).
    public var sensitivity: Double
    public var profile: Profile
    /// `v_ref`, pt/s (spec default 1500).
    public var referenceVelocity: Double

    public init(sensitivity: Double = 5, profile: Profile = .default, referenceVelocity: Double = 1500) {
        self.sensitivity = sensitivity
        self.profile = profile
        self.referenceVelocity = referenceVelocity
    }

    /// spec §5.4: `base(s) = 0.6 · (4.0/0.6)^((s-1)/9)`, matching the doc's sample table exactly
    /// for integer `s` in 1...10 (0.60, 0.74, 0.91, 1.13, 1.39, 1.72, 2.12, 2.62, 3.24, 4.00).
    public static func base(sensitivity s: Double) -> Double {
        let clamped = Swift.min(Swift.max(s, 1), 10)
        return 0.6 * pow(4.0 / 0.6, (clamped - 1) / 9)
    }

    public var base: Double { Self.base(sensitivity: sensitivity) }

    /// spec §5.4: `accel(v) = 1 + a · min(v/v_ref, 1)²`.
    public func accel(velocity v: Double) -> Double {
        let a = profile.a
        guard a > 0 else { return 1 }
        let ratio = Swift.min(Swift.max(v, 0) / referenceVelocity, 1)
        return 1 + a * ratio * ratio
    }

    /// Combined `base(s) · accel(v)`. Gyro-source samples bypass the curve entirely per spec
    /// ("accel = 1 for source == gyro") — pass `isGyroSource: true` to get gain `1.0` regardless of
    /// sensitivity or velocity, matching "the host applies no acceleration to gyro datagrams".
    public func gain(velocity v: Double, isGyroSource: Bool = false) -> Double {
        guard !isGyroSource else { return 1.0 }
        return base * accel(velocity: v)
    }

    /// Applies the curve to one per-sample delta (points), deriving the finger velocity from the
    /// delta's own magnitude and `sampleInterval` (the client-timestamp gap to the previous datagram
    /// of the same source, clamped 4...50 ms per spec). The first datagram of a burst forces
    /// `accel = 1` (spec: "the first datagram of a burst uses `accel = 1`").
    public func apply(
        _ delta: Delta,
        sampleInterval: TimeInterval,
        isFirstOfBurst: Bool = false,
        isGyroSource: Bool = false
    ) -> Delta {
        guard !isGyroSource else { return delta }
        guard !isFirstOfBurst else { return delta * base }
        let dt = Swift.min(Swift.max(sampleInterval, 0.004), 0.050)
        let velocity = Swift.min(Swift.max(delta.length / dt, 0), 20_000) // spec §5.3.2 clamp
        return delta * gain(velocity: velocity)
    }
}
