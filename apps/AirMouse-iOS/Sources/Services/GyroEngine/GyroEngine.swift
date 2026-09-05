// Services/GyroEngine/GyroEngine.swift
// CoreMotion → GyroMapper wrapper (spec §4.3, arch §3.2 "GyroEngine"). `@MainActor @Observable`
// for the UI-facing state machine (`GyroEngineState`, calibration progress, availability);
// per-sample math is isolated in the `GyroProcessor` actor so 100 Hz updates never touch the
// main thread's `GyroMapper` mutation directly.
//
// Deviations from a literal reading of the assignment, all spec-driven:
// - CoreMotion updates are gated on tab-visible + app-active only (spec §4.3.1: "Updates run
//   only while the Air Mouse tab... is visible and the app is active; stopped otherwise
//   (NFR-PERF-007)"), NOT on clutch engagement — the mapper needs continuous samples for
//   stillness-driven bias tracking and the raw-fallback indicator even while disengaged, and
//   §4.3.1 does not gate on the clutch. `GyroMapper.update` itself still only emits deltas while
//   engaged (its own `isEngaged` guard), so no motion reaches `MotionEnqueuing`'s sink unless the clutch
//   is on either way.
// - `UserSettings.GyroSettings` (Services/DocumentStore/UserSettings.swift, not owned by this
//   assignment) only models sensitivity/smoothing/deadZone — it has no `clutchMode`,
//   `recenterMode`, or `lockOrientation` fields from spec §4.1.9's Gyro settings section. Those
//   live in `GyroEngineSettings`/`@AppStorage` in this module instead (see
//   `AirMouseViewModel`); recommend the Settings-owning agent add the missing fields so a single
//   `SettingsSnapshot` round-trips the whole section.
// - spec §4.3.5's raw-`gyroData`-minus-bias fallback is approximated: `CoreMotionSampler` only
//   starts device-motion updates (one CMMotionManager stream), and `GyroMapper.update` takes a
//   single `rotationRate` input with no notion of its source, so this only flips the
//   `isCalibratingIndicatorVisible` flag (never blocks input, FR-GY-011) rather than switching to
//   a second raw-gyro stream — `deviceMotion.rotationRate` is already CoreMotion's best available
//   estimate in both cases.
// - Bias is not persisted across launches/recalibrations (nothing in spec §4.3.5/§4.3.7 says it
//   should be); each `GyroEngine` instance starts with a fresh `BiasEstimator` and relies on the
//   calibration hold / ongoing stillness EMA to reconverge, consistent with "residual bias
//   appears as slow creep, which is what the clutch handles" (research doc).

import AirMouseFilters
import AirMouseProtocol
import Foundation
import Observation
import UIKit

@MainActor
@Observable
public final class GyroEngine: GyroEngineProviding {
    // MARK: - Public UI-facing state

    /// `CMMotionManager().isDeviceMotionAvailable` (spec §4.1: FR-GY-012 tab visibility gate).
    public let isGyroAvailable: Bool
    public private(set) var state: GyroEngineState = .idle
    /// 0...1 while `state == .calibrating`.
    public private(set) var calibrationProgress: Double = 0
    /// spec §4.3.5's "Calibrating" indicator (magnetometer uncalibrated > 2 s / attitude
    /// unavailable). Distinct from `state == .calibrating`, which is the hold-still UX.
    public private(set) var isRawFallbackIndicatorVisible: Bool = false
    /// Whether `CMMotionManager` updates are currently flowing (diagnostics / tests).
    public private(set) var isSampling: Bool = false
    /// Most recent non-zero delta forwarded to the sink, for an optional on-screen debug readout.
    public private(set) var lastDelta: Delta = .zero
    /// Bumped every time `recenter()` runs (double-tap, shake, or "Recalibrate now" is a
    /// calibration, not this) — a lightweight seam for tests to confirm the double-tap/shake
    /// debounce actually fired without depending on `GyroMapper`'s internal, unobservable state.
    public private(set) var recenterCallCount = 0

    public var clutchMode: ClutchMode
    public var recenterMode: GyroRecenterMode

    /// Called once, the moment a calibration hold (initial or "Recalibrate now") completes.
    public var onCalibrationCompleted: (() -> Void)?

    // MARK: - Dependencies

    private let sampler: any MotionSampling
    private let processor: GyroProcessor
    private let sink: any MotionEnqueuing
    private let clock: any Clock
    private let operationQueue: OperationQueue

    // MARK: - Lifecycle bookkeeping

    private var isScreenVisible = false
    private var isAppActive = true
    private var lastPressEndedAt: TimeInterval?
    private var lastShakeRecenterAt: TimeInterval = -.infinity
    private var motionSuppressedUntil: TimeInterval = -.infinity
    // `nonisolated(unsafe)`: only ever mutated from MainActor-isolated code (`init`/
    // `registerAppLifecycleObservers()`), but also read from `deinit`, which is always
    // `nonisolated` in Swift — safe here since `deinit` only runs once there are no other
    // references left to race with. `@ObservationIgnored` keeps the `@Observable` macro from
    // re-wrapping storage access in a way that would otherwise make `nonisolated(unsafe)` a no-op.
    @ObservationIgnored
    nonisolated(unsafe) private var backgroundToken: NSObjectProtocol?
    @ObservationIgnored
    nonisolated(unsafe) private var foregroundToken: NSObjectProtocol?

    /// spec §4.3.6: "Double-tap on the clutch (two touches within 300 ms) → recenter."
    public static let doubleTapWindow: TimeInterval = 0.300
    /// spec §4.3.6: "Around any click in gyro mode, motion is suppressed for 80 ms (FR-GY-008)."
    public static let motionSuppressAfterClick: TimeInterval = 0.080
    /// spec §4.3.6: "Shake → recenter... debounced 1 s."
    public static let shakeDebounce: TimeInterval = 1.0
    /// spec §4.3.1.
    public static let sampleInterval: TimeInterval = 1.0 / 100.0

    public init(
        sampler: any MotionSampling = CoreMotionSampler(),
        sink: any MotionEnqueuing = NoOpMotionEnqueuer(),
        clock: any Clock = SystemClock(),
        settings: GyroEngineSettings = GyroEngineSettings(),
        observeAppLifecycle: Bool = true
    ) {
        self.sampler = sampler
        self.sink = sink
        self.clock = clock
        self.isGyroAvailable = sampler.isDeviceMotionAvailable
        self.clutchMode = settings.clutchMode
        self.recenterMode = settings.recenterMode
        self.processor = GyroProcessor(config: GyroProcessor.Config(
            deadZoneDegPerSec: settings.deadZoneDegPerSec,
            sensitivity: settings.sensitivity,
            minCutoffSlider: settings.smoothingSlider,
            orientation: settings.isOrientationLocked ? .suspended : .portrait,
            clutchMode: settings.clutchMode
        ))
        let queue = OperationQueue()
        queue.name = "com.airmouse.app.gyro"
        queue.qualityOfService = .userInteractive
        queue.maxConcurrentOperationCount = 1
        self.operationQueue = queue

        if observeAppLifecycle {
            registerAppLifecycleObservers()
        }
    }

    deinit {
        if let backgroundToken { NotificationCenter.default.removeObserver(backgroundToken) }
        if let foregroundToken { NotificationCenter.default.removeObserver(foregroundToken) }
    }

    // MARK: - GyroEngineProviding (spec: tab appear/disappear per arch §3.2's AirMouse feature row)

    public func start() async {
        isScreenVisible = true
        beginSamplingIfNeeded()
    }

    public func stop() async {
        isScreenVisible = false
        endSampling()
        await processor.disengageClutch()
        await processor.cancelCalibration()
        state = .idle
        calibrationProgress = 0
    }

    // MARK: - Clutch (spec §4.3.6)

    /// Call on clutch button touch-down.
    public func clutchPressBegan() {
        guard state != .calibrating else { return }
        if clutchMode == .hold { engageClutch() }
    }

    /// Call on clutch button touch-up (also drives the double-tap → recenter debounce).
    public func clutchPressEnded() {
        guard state != .calibrating else { return }
        switch clutchMode {
        case .hold: disengageClutch()
        case .toggle: toggleClutch()
        }
        guard recenterMode.respondsToDoubleTap else { return }
        let now = clock.now()
        if let last = lastPressEndedAt, now - last <= Self.doubleTapWindow {
            recenter()
            lastPressEndedAt = nil
        } else {
            lastPressEndedAt = now
        }
    }

    private func engageClutch() {
        Task {
            await processor.engageClutch()
            state = .armed
        }
    }

    private func disengageClutch() {
        guard state == .armed || state == .moving else { return }
        let timestamp = clock.now()
        Task {
            await processor.disengageClutch()
            state = .idle
            // spec §4.3.6: "release → ... one datagram with motionEnd + control motionEnd."
            await sink.enqueue(dx: 0, dy: 0, flags: .motionEnd, source: .gyro, timestamp: timestamp)
        }
    }

    private func toggleClutch() {
        let timestamp = clock.now()
        Task {
            await processor.toggleClutch()
            let engaged = await processor.isEngaged
            if engaged {
                state = .armed
            } else {
                state = .idle
                await sink.enqueue(dx: 0, dy: 0, flags: .motionEnd, source: .gyro, timestamp: timestamp)
            }
        }
    }

    /// spec §4.3.6: flushes filter/integrator history for a clean restart.
    public func recenter() {
        recenterCallCount += 1
        Task { await processor.recenter() }
    }

    /// Hook for a shake-gesture detector (UIKit `motionEnded`, spec §4.1.5) — debounced 1 s and
    /// gated by `recenterMode`.
    public func handleShakeGesture() {
        guard recenterMode.respondsToShake else { return }
        let now = clock.now()
        guard now - lastShakeRecenterAt >= Self.shakeDebounce else { return }
        lastShakeRecenterAt = now
        recenter()
    }

    /// spec §4.3.6 FR-GY-008: call around any click in gyro mode to suppress motion for 80 ms.
    public func suppressMotionAfterClick() {
        motionSuppressedUntil = clock.now() + Self.motionSuppressAfterClick
    }

    // MARK: - Live settings (spec §4.1.9)

    public func setSensitivity(_ value: Double) {
        Task { await processor.setSensitivity(value) }
    }

    public func setDeadZone(_ value: Double) {
        Task { await processor.setDeadZone(value) }
    }

    public func setSmoothingSlider(_ value: Double) {
        Task { await processor.setSmoothingSlider(value) }
    }

    public func setClutchMode(_ mode: ClutchMode) {
        clutchMode = mode
        Task { await processor.setClutchMode(mode) }
    }

    public func setOrientationLocked(_ locked: Bool, currentOrientation: Orientation) {
        Task { await processor.setOrientation(locked ? .suspended : currentOrientation) }
    }

    public func updateOrientation(_ orientation: Orientation) {
        Task { await processor.setOrientation(orientation) }
    }

    // MARK: - Calibration (spec §4.3.7)

    public func startCalibration() {
        guard isGyroAvailable else { return }
        state = .calibrating
        calibrationProgress = 0
        Task { await processor.beginCalibration() }
    }

    public func cancelCalibration() {
        guard state == .calibrating else { return }
        Task {
            await processor.cancelCalibration()
            state = .idle
            calibrationProgress = 0
        }
    }

    // MARK: - Sampling lifecycle

    private func beginSamplingIfNeeded() {
        guard isGyroAvailable, isScreenVisible, isAppActive, !isSampling else { return }
        isSampling = true
        sampler.startUpdates(interval: Self.sampleInterval, queue: operationQueue) { [weak self] sample in
            guard let self else { return }
            Task { await self.ingest(sample) }
        }
    }

    private func endSampling() {
        guard isSampling else { return }
        sampler.stopUpdates()
        isSampling = false
    }

    private func ingest(_ sample: MotionSampleData) async {
        let result = await processor.ingest(sample)
        apply(result, sampleTimestamp: sample.timestamp)
    }

    private func apply(_ result: GyroProcessor.Result, sampleTimestamp: TimeInterval) {
        isRawFallbackIndicatorVisible = result.isRawFallbackActive

        if let progress = result.calibrationProgress {
            state = .calibrating
            calibrationProgress = progress
            if result.calibrationCompleted {
                calibrationProgress = 1
                state = result.isEngaged ? .armed : .idle
                onCalibrationCompleted?()
            }
            return
        }

        guard result.isEngaged else {
            if state != .idle { state = .idle }
            return
        }

        guard let delta = result.delta, delta != .zero else {
            state = .armed
            return
        }

        guard clock.now() >= motionSuppressedUntil else {
            // spec FR-GY-008: swallow the delta, but stay armed rather than snapping to .moving.
            state = .armed
            return
        }

        state = .moving
        lastDelta = delta
        Task { await sink.enqueue(dx: delta.dx, dy: delta.dy, flags: [], source: .gyro, timestamp: sampleTimestamp) }
    }

    // MARK: - App lifecycle (spec §4.3.1 "stopped otherwise")

    private func registerAppLifecycleObservers() {
        backgroundToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleDidEnterBackground() }
        }
        foregroundToken = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWillEnterForeground() }
        }
    }

    private func handleDidEnterBackground() {
        isAppActive = false
        endSampling()
    }

    private func handleWillEnterForeground() {
        isAppActive = true
        beginSamplingIfNeeded()
    }
}
