// Services/GyroEngine/GyroCalibrationSession.swift
// Calibration UX bookkeeping, spec §4.3.7: "hold the phone... 1 s progress ring; during that
// second the bias estimator runs... a shaky hold restarts the ring (|ω| > 5°/s)."
//
// This type only tracks progress/shake-restart; the actual bias convergence during the hold is
// delegated to `GyroMapper`'s own stillness-gated EMA (spec §4.3.5) by keeping it engaged (but not
// forwarding its output) for the duration — see `GyroProcessor`. `GyroMapper`/`BiasEstimator` are
// finished, owned-elsewhere types (`Packages/AirControlKit/Sources/AirControlFilters`) that do not
// expose a separate faster-alpha "seed" pass, so this reuses the mapper's normal EMA rather than
// re-implementing bias math here — see the deviation note in the final report.
import Foundation
import simd

public struct GyroCalibrationSession: Sendable, Equatable {
    /// spec §11.3 "Calibration hold": 1 s, fixed.
    public static let holdDuration: TimeInterval = 1.0
    /// spec §4.3.7 "shaky hold restarts the ring (|ω| > 5°/s)".
    public static let shakeThresholdRadPerSec: Double = 5.0 * .pi / 180.0

    public private(set) var elapsed: TimeInterval = 0
    /// 0...1; the progress ring's fill fraction.
    public private(set) var progress: Double = 0

    public init() {}

    /// Feeds one sample's rotation rate and elapsed time since the previous sample. Returns
    /// `true` exactly once, the sample on which the hold completes.
    @discardableResult
    public mutating func ingest(rotationRate: SIMD3<Double>, dt: TimeInterval) -> Bool {
        guard dt > 0 else { return false }
        let magnitude = simd_length(rotationRate)
        guard magnitude <= Self.shakeThresholdRadPerSec else {
            reset()
            return false
        }
        elapsed = Swift.min(elapsed + dt, Self.holdDuration)
        progress = elapsed / Self.holdDuration
        return elapsed >= Self.holdDuration
    }

    public mutating func reset() {
        elapsed = 0
        progress = 0
    }
}
