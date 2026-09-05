// Services/GyroEngine/GyroProcessor.swift
// The per-sample math, isolated off the main actor so 100 Hz `GyroMapper.update` calls (spec
// §4.3.1/§4.3.2) never contend with SwiftUI. `GyroEngine` (MainActor) owns lifecycle/UI state and
// forwards every `MotionSampleData` here; this actor owns the mutable `GyroMapper` value and the
// calibration/raw-fallback bookkeeping, and reports back a plain `Result` for `GyroEngine` to
// apply to its `@Observable` state and hand to `GyroMotionSink`.
import AirMouseFilters
import Foundation
import simd

public actor GyroProcessor {
    public struct Config: Sendable, Equatable {
        public var deadZoneDegPerSec: Double
        public var gainG0PxPerRad: Double
        public var sensitivity: Double
        public var minCutoffSlider: Double
        public var orientation: Orientation
        public var clutchMode: ClutchMode

        public init(
            deadZoneDegPerSec: Double = 0.5,
            gainG0PxPerRad: Double = GyroMapper.referenceGain,
            sensitivity: Double = 5,
            minCutoffSlider: Double = 5,
            orientation: Orientation = .portrait,
            clutchMode: ClutchMode = .hold
        ) {
            self.deadZoneDegPerSec = deadZoneDegPerSec
            self.gainG0PxPerRad = gainG0PxPerRad
            self.sensitivity = sensitivity
            self.minCutoffSlider = minCutoffSlider
            self.orientation = orientation
            self.clutchMode = clutchMode
        }
    }

    public struct Result: Sendable, Equatable {
        public var delta: Delta?
        public var isEngaged: Bool
        /// Non-nil while a calibration hold (initial or "Recalibrate now") is in progress.
        public var calibrationProgress: Double?
        public var calibrationCompleted: Bool
        /// spec §4.3.5: magnetometer uncalibrated > 2 s or attitude unavailable → "Calibrating"
        /// indicator (never blocks input; motion keeps flowing regardless of this flag).
        public var isRawFallbackActive: Bool
    }

    private var mapper: GyroMapper
    private var calibration = GyroCalibrationSession()
    private var isCalibrating = false
    private var wasEngagedBeforeCalibration = false
    private var uncalibratedSince: TimeInterval?
    private var isRawFallbackActive = false

    public init(config: Config = Config()) {
        self.mapper = GyroMapper(
            deadZoneDegPerSec: config.deadZoneDegPerSec,
            gainG0PxPerRad: config.gainG0PxPerRad,
            sensitivity: config.sensitivity,
            minCutoffSlider: config.minCutoffSlider,
            orientation: config.orientation,
            clutchMode: config.clutchMode
        )
    }

    // MARK: - Clutch / recenter

    public func engageClutch() {
        guard !isCalibrating else { return }
        mapper.engage()
    }

    public func disengageClutch() {
        guard !isCalibrating else { return }
        mapper.disengage()
    }

    public func toggleClutch() {
        guard !isCalibrating else { return }
        mapper.toggleEngagement()
    }

    public var isEngaged: Bool { mapper.isEngaged }

    /// spec §4.3.6: double-tap / shake → recenter (flush integrator, keep learned bias).
    public func recenter() {
        mapper.recenter()
    }

    // MARK: - Live settings (spec §4.1.9 Gyro section)

    public func setSensitivity(_ value: Double) {
        mapper.sensitivity = value
    }

    public func setDeadZone(_ value: Double) {
        mapper.deadZoneDegPerSec = value
    }

    public func setClutchMode(_ mode: ClutchMode) {
        mapper.clutchMode = mode
    }

    public func setOrientation(_ orientation: Orientation) {
        mapper.setOrientation(orientation)
    }

    /// Changing the One-Euro `minCutoff` (spec §4.3.4) requires a fresh `GyroMapper` — its filters
    /// are private and only parameterized at init. Preserves engagement/orientation/other config.
    public func setSmoothingSlider(_ slider: Double) {
        let wasEngaged = mapper.isEngaged
        var rebuilt = GyroMapper(
            deadZoneDegPerSec: mapper.deadZoneDegPerSec,
            gainG0PxPerRad: mapper.gainG0PxPerRad,
            sensitivity: mapper.sensitivity,
            minCutoffSlider: slider,
            orientation: mapper.orientation,
            clutchMode: mapper.clutchMode
        )
        if wasEngaged { rebuilt.engage() }
        mapper = rebuilt
    }

    // MARK: - Calibration (spec §4.3.7)

    public func beginCalibration() {
        guard !isCalibrating else { return }
        wasEngagedBeforeCalibration = mapper.isEngaged
        isCalibrating = true
        calibration.reset()
        if !mapper.isEngaged { mapper.engage() }
    }

    public func cancelCalibration() {
        guard isCalibrating else { return }
        isCalibrating = false
        if !wasEngagedBeforeCalibration { mapper.disengage() }
        calibration.reset()
    }

    // MARK: - Sample ingestion

    public func ingest(_ sample: MotionSampleData) -> Result {
        updateRawFallbackTracking(sample: sample)

        if isCalibrating {
            let dt = lastCalibrationTimestamp.map { max(sample.timestamp - $0, 0) } ?? 0
            lastCalibrationTimestamp = sample.timestamp
            let completed = calibration.ingest(rotationRate: sample.rotationRate, dt: dt)
            // Run the mapper so its stillness-gated bias EMA (spec §4.3.5) seeds during the hold;
            // the resulting delta is intentionally discarded (spec: seeding, not motion output).
            _ = mapper.update(
                rotationRate: sample.rotationRate,
                gravity: sample.gravity,
                userAcceleration: sample.userAcceleration,
                timestamp: sample.timestamp
            )
            if completed {
                isCalibrating = false
                if !wasEngagedBeforeCalibration { mapper.disengage() }
            }
            return Result(
                delta: nil,
                isEngaged: wasEngagedBeforeCalibration,
                calibrationProgress: calibration.progress,
                calibrationCompleted: completed,
                isRawFallbackActive: isRawFallbackActive
            )
        }

        let delta = mapper.update(
            rotationRate: sample.rotationRate,
            gravity: sample.gravity,
            userAcceleration: sample.userAcceleration,
            timestamp: sample.timestamp
        )
        return Result(
            delta: delta,
            isEngaged: mapper.isEngaged,
            calibrationProgress: nil,
            calibrationCompleted: false,
            isRawFallbackActive: isRawFallbackActive
        )
    }

    private var lastCalibrationTimestamp: TimeInterval?

    private func updateRawFallbackTracking(sample: MotionSampleData) {
        if sample.magneticFieldAccuracy == .uncalibrated {
            if uncalibratedSince == nil { uncalibratedSince = sample.timestamp }
        } else {
            uncalibratedSince = nil
        }
        let uncalibratedTooLong = uncalibratedSince.map { sample.timestamp - $0 >= 2.0 } ?? false
        isRawFallbackActive = uncalibratedTooLong || !sample.attitudeAvailable
    }
}
