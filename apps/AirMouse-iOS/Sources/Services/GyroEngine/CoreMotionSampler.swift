// Services/GyroEngine/CoreMotionSampler.swift
// The real `MotionSampling` implementation: `CMMotionManager` configured exactly per spec §4.3.1
// ("`deviceMotionUpdateInterval = 1/100`; `startDeviceMotionUpdates(using:
// .xArbitraryCorrectedZVertical, to: OperationQueue(qos: .userInteractive))`. Use `rotationRate`
// (bias-corrected) and `gravity`."). This is the only file in the module that imports CoreMotion.

import CoreMotion
import Foundation
import simd

public final class CoreMotionSampler: MotionSampling {
    private let manager = CMMotionManager()

    public init() {}

    public var isDeviceMotionAvailable: Bool { manager.isDeviceMotionAvailable }
    public var isActive: Bool { manager.isDeviceMotionActive }

    public func startUpdates(interval: TimeInterval, queue: OperationQueue, handler: @escaping @Sendable (MotionSampleData) -> Void) {
        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
        manager.deviceMotionUpdateInterval = interval
        // spec §4.3.1: `.xArbitraryCorrectedZVertical` (magnetometer-corrected reference frame;
        // falls back to raw gyro integration internally when the compass is unreliable, which is
        // exactly the accuracy CoreMotion surfaces via `magneticField.accuracy` for §4.3.5's
        // "switch to raw gyroData" indicator).
        manager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: queue) { motion, _ in
            guard let motion else { return }
            let sample = MotionSampleData(
                rotationRate: SIMD3(motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z),
                gravity: SIMD3(motion.gravity.x, motion.gravity.y, motion.gravity.z),
                userAcceleration: SIMD3(motion.userAcceleration.x, motion.userAcceleration.y, motion.userAcceleration.z),
                attitudeAvailable: true, // `motion.attitude` always exists on a delivered `CMDeviceMotion`
                magneticFieldAccuracy: MagneticFieldCalibrationAccuracy(motion.magneticField.accuracy),
                timestamp: motion.timestamp
            )
            handler(sample)
        }
    }

    public func stopUpdates() {
        manager.stopDeviceMotionUpdates()
    }
}

private extension MagneticFieldCalibrationAccuracy {
    init(_ accuracy: CMMagneticFieldCalibrationAccuracy) {
        switch accuracy {
        case .uncalibrated: self = .uncalibrated
        case .low: self = .low
        case .medium: self = .medium
        case .high: self = .high
        @unknown default: self = .uncalibrated
        }
    }
}
