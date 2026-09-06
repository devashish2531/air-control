// Services/GyroEngine/MotionSampling.swift
// Thin seam over `CMMotionManager` (spec §4.3.1) so `GyroEngine`'s math and lifecycle can be
// exercised in the simulator/unit tests without a real gyroscope. `GyroEngine` only ever talks to
// `MotionSampling`; `CoreMotionSampler` is the sole file that imports CoreMotion.

import Foundation
import simd

/// Mirrors `CMMagneticFieldCalibrationAccuracy` (spec §4.3.5's "`magneticField.accuracy ==
/// .uncalibrated`"), decoupled from CoreMotion so `MotionSampleData` stays a plain Sendable value
/// usable from `FakeMotionSampler` in tests.
public enum MagneticFieldCalibrationAccuracy: Sendable, Equatable {
    case uncalibrated
    case low
    case medium
    case high
}

/// One `CMDeviceMotion`-equivalent sample, decoupled from CoreMotion. All vectors are in the
/// device frame; `rotationRate` is rad/s, `gravity` and `userAcceleration` are in g.
public struct MotionSampleData: Sendable, Equatable {
    public var rotationRate: SIMD3<Double>
    public var gravity: SIMD3<Double>
    public var userAcceleration: SIMD3<Double>
    /// spec §4.3.5: "`attitude` is unavailable" is one of the two raw-fallback triggers.
    public var attitudeAvailable: Bool
    public var magneticFieldAccuracy: MagneticFieldCalibrationAccuracy
    /// Seconds, monotonic for the sampler instance (`CMDeviceMotion.timestamp` is
    /// `ProcessInfo.systemUptime`-relative, which satisfies `Clock`'s "non-decreasing" contract).
    public var timestamp: TimeInterval

    public init(
        rotationRate: SIMD3<Double>,
        gravity: SIMD3<Double>,
        userAcceleration: SIMD3<Double> = .zero,
        attitudeAvailable: Bool = true,
        magneticFieldAccuracy: MagneticFieldCalibrationAccuracy = .high,
        timestamp: TimeInterval
    ) {
        self.rotationRate = rotationRate
        self.gravity = gravity
        self.userAcceleration = userAcceleration
        self.attitudeAvailable = attitudeAvailable
        self.magneticFieldAccuracy = magneticFieldAccuracy
        self.timestamp = timestamp
    }
}

/// Seam over `CMMotionManager`'s device-motion updates (spec §4.3.1). Conformances must deliver
/// samples in arrival order to whatever queue `startUpdates(queue:handler:)` is given — real
/// CoreMotion already guarantees this: the async `handler` closure is not required to be
/// `@Sendable` at the call site because `startUpdates` itself takes ownership of a `@Sendable`
/// closure it stores, matching `CMMotionManager`'s own non-`Sendable` delegate-style API.
public protocol MotionSampling: AnyObject {
    /// `CMMotionManager().isDeviceMotionAvailable` (spec §4.1: FR-GY-012 tab visibility gate).
    var isDeviceMotionAvailable: Bool { get }
    /// Whether updates are currently flowing (mirrors `CMMotionManager.isDeviceMotionActive`).
    var isActive: Bool { get }

    /// Starts delivering samples at `interval` seconds (spec: `1/100`) to `queue`, invoking
    /// `handler` for every sample. Safe to call again while active (restarts with the new
    /// interval/handler); `CoreMotionSampler` does so via `stopUpdates()` + a fresh start.
    func startUpdates(interval: TimeInterval, queue: OperationQueue, handler: @escaping @Sendable (MotionSampleData) -> Void)
    func stopUpdates()
}
