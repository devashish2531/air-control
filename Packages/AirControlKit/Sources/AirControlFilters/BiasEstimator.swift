import simd

/// Stillness-driven drift bias estimator for the gyro engine (spec §4.3.5): "While `|f₁| == 0` on
/// both axes for ≥ 300 ms, update `bias ← bias + 0.05·(ω − bias)` per sample and subtract `bias`
/// before the dead zone thereafter."
///
/// Tracked per mapped axis (yaw, pitch) rather than the raw 3-axis rotation rate, since that is
/// the space the dead zone and gain operate in.
public struct BiasEstimator: Sendable, Equatable {
    /// EMA coefficient applied during normal stillness tracking (spec default 0.05).
    public var alpha: Double
    public private(set) var bias: SIMD2<Double> = .zero // (yaw, pitch), rad/s

    public init(alpha: Double = 0.05) {
        self.alpha = alpha
    }

    /// Updates the estimate with one still sample, using `alpha` (or `overrideAlpha` during the
    /// faster-converging calibration hold, spec §4.3.7's α = 0.2 seed).
    public mutating func update(rawYaw: Double, rawPitch: Double, alpha overrideAlpha: Double? = nil) {
        let a = overrideAlpha ?? alpha
        bias.x += a * (rawYaw - bias.x)
        bias.y += a * (rawPitch - bias.y)
    }

    public mutating func reset() {
        bias = .zero
    }
}
