// Features/AirPointer/AirPointerViewModel.swift
// Owns `GyroEngine`'s lifecycle and translates the Air Pointer tab's gestures (clutch, click area,
// scroll strip, recenter) into engine calls / control-channel messages + haptics (spec §4.1.5,
// §4.3.6, §4.6). Per arch §3.2's MVVM pattern: `@MainActor @Observable`, constructed by the view
// from `AppEnvironment`.
//
// Click/scroll-phase messages go through `ControlMessageSink` (Features/Touchpad, another agent's
// module — same app target, no import needed) rather than a redundant protocol of this module's
// own: it already declares exactly `sendClick`/`sendScrollPhase`. Scroll *deltas* (the strip's
// drag distance) travel on the motion channel per spec §3.6, so they go through the same
// `MotionEnqueuing` sink as `GyroEngine`'s pointer deltas (`enqueueScroll`, source `.touch` since
// this is a finger-drag scroll, not gyro rotation).
import AirControlFilters
import AirControlProtocol
import Foundation
import Observation
import UIKit

@MainActor
@Observable
public final class AirPointerViewModel {
    public let engine: GyroEngine
    public let localSettings: AirPointerLocalSettings

    private let userSettings: UserSettings
    private let haptics: any HapticsService
    private let controlSink: any ControlMessageSink
    private let motionSink: any MotionEnqueuing
    private let clock: any Clock

    /// spec §4.1.5: "hold ≥ 250 ms = drag while held" on the click area.
    public static let holdToDragThreshold: Duration = .milliseconds(250)

    public private(set) var isPrimaryClickDragging = false
    public private(set) var isSecondaryClickDragging = false
    public private(set) var isScrolling = false

    private var primaryHoldTask: Task<Void, Never>?
    private var secondaryHoldTask: Task<Void, Never>?
    private var lastScrollTranslationY: Double = 0

    public init(
        engine: GyroEngine,
        localSettings: AirPointerLocalSettings,
        userSettings: UserSettings,
        haptics: any HapticsService,
        controlSink: any ControlMessageSink = NoOpControlMessageSink(),
        motionSink: any MotionEnqueuing = NoOpMotionEnqueuer(),
        clock: any Clock = SystemClock()
    ) {
        self.engine = engine
        self.localSettings = localSettings
        self.userSettings = userSettings
        self.haptics = haptics
        self.controlSink = controlSink
        self.motionSink = motionSink
        self.clock = clock

        engine.clutchMode = localSettings.clutchMode
        engine.recenterMode = localSettings.recenterMode
        engine.onCalibrationCompleted = { [weak self] in
            self?.userSettings.tutorialGyroDone = true
        }
        applyGyroSettings()
    }

    // MARK: - Tab lifecycle (arch §3.2: "owns GyroEngine lifecycle — starts on appear, stops on disappear")

    public func onAppear() async {
        await engine.start()
        if !userSettings.tutorialGyroDone {
            engine.startCalibration()
        }
        beginObservingOrientation()
    }

    public func onDisappear() async {
        endObservingOrientation()
        await engine.stop()
    }

    public func recalibrateNow() {
        engine.startCalibration()
    }

    /// Whether the first-use calibration hint/hold has already been completed (spec §4.1.5:
    /// "'hold like a remote' hint on first use").
    public var hasCompletedGyroTutorial: Bool { userSettings.tutorialGyroDone }

    // MARK: - Settings sync (spec §4.1.9 Gyro section)

    public func applyGyroSettings() {
        let gyro = userSettings.snapshot.gyro
        engine.setSensitivity(Double(gyro.sensitivity))
        engine.setSmoothingSlider(Double(gyro.smoothing))
        engine.setDeadZone(gyro.deadZoneDegreesPerSecond)
    }

    /// Live-bound sliders (spec §4.1.9 "Sensitivity 1–10... Smoothing 0–10... Dead zone 0–3°/s").
    /// Forwards through `UserSettings` so the value round-trips through the same persisted
    /// snapshot the (separately-owned) Settings screen reads.
    public var sensitivity: Double {
        get { Double(userSettings.snapshot.gyro.sensitivity) }
        set {
            let range = GyroSettings.sensitivityRange
            userSettings.snapshot.gyro.sensitivity = Int(newValue.rounded()).clamped(to: range)
            applyGyroSettings()
        }
    }

    public var smoothing: Double {
        get { Double(userSettings.snapshot.gyro.smoothing) }
        set {
            let range = GyroSettings.smoothingRange
            userSettings.snapshot.gyro.smoothing = Int(newValue.rounded()).clamped(to: range)
            applyGyroSettings()
        }
    }

    public var deadZone: Double {
        get { userSettings.snapshot.gyro.deadZoneDegreesPerSecond }
        set {
            userSettings.snapshot.gyro.deadZoneDegreesPerSecond = newValue.clamped(to: GyroSettings.deadZoneRange)
            applyGyroSettings()
        }
    }

    public func setClutchMode(_ mode: ClutchMode) {
        localSettings.clutchMode = mode
        engine.setClutchMode(mode)
    }

    public func setRecenterMode(_ mode: GyroRecenterMode) {
        localSettings.recenterMode = mode
        engine.recenterMode = mode
    }

    public func setOrientationLocked(_ locked: Bool) {
        localSettings.isOrientationLocked = locked
        engine.setOrientationLocked(locked, currentOrientation: currentInterfaceOrientation())
    }

    // MARK: - Clutch (spec §4.3.6)

    public func clutchPressBegan() {
        haptics.prepare(.clutchEngage)
        if engine.clutchMode == .hold {
            haptics.fire(.clutchEngage)
        }
        engine.clutchPressBegan()
    }

    public func clutchPressEnded() {
        switch engine.clutchMode {
        case .hold:
            haptics.fire(.clutchRelease)
        case .toggle:
            // `engine.state` still reflects the pre-toggle value here — the actual toggle runs
            // asynchronously inside `clutchPressEnded()` below.
            let willEngage = engine.state == .idle
            haptics.fire(willEngage ? .clutchEngage : .clutchRelease)
        }
        engine.clutchPressEnded()
    }

    public func shakeDetected() {
        engine.handleShakeGesture()
    }

    public func recenterButtonTapped() {
        // spec §4.6's table has no dedicated "recenter" haptic; a selection tick is the closest
        // fit among the enumerated events for a discrete, non-destructive action.
        haptics.prepare(.modifierToggle)
        haptics.fire(.modifierToggle)
        engine.recenter()
    }

    // MARK: - Click area (spec §4.1.5: "tap = click, hold ≥ 250 ms = drag while held")

    public func primaryPressBegan() {
        haptics.prepare(.buttonDown)
        haptics.fire(.buttonDown)
        engine.suppressMotionAfterClick()
        primaryHoldTask?.cancel()
        primaryHoldTask = Task { [weak self] in
            try? await Task.sleep(for: Self.holdToDragThreshold)
            guard let self, !Task.isCancelled else { return }
            self.isPrimaryClickDragging = true
            self.controlSink.sendClick(Click(button: .left, action: .down, count: 1, modifiers: []))
        }
    }

    public func primaryPressEnded() {
        primaryHoldTask?.cancel()
        primaryHoldTask = nil
        haptics.fire(.buttonUp)
        engine.suppressMotionAfterClick()
        let wasDragging = isPrimaryClickDragging
        isPrimaryClickDragging = false
        if wasDragging {
            controlSink.sendClick(Click(button: .left, action: .up, count: 1, modifiers: []))
        } else {
            controlSink.sendClick(Click(button: .left, action: .tap, count: 1, modifiers: []))
        }
    }

    public func secondaryPressBegan() {
        haptics.prepare(.buttonDown)
        haptics.fire(.buttonDown)
        engine.suppressMotionAfterClick()
        secondaryHoldTask?.cancel()
        secondaryHoldTask = Task { [weak self] in
            try? await Task.sleep(for: Self.holdToDragThreshold)
            guard let self, !Task.isCancelled else { return }
            self.isSecondaryClickDragging = true
            self.controlSink.sendClick(Click(button: .right, action: .down, count: 1, modifiers: []))
        }
    }

    public func secondaryPressEnded() {
        secondaryHoldTask?.cancel()
        secondaryHoldTask = nil
        haptics.fire(.buttonUp)
        engine.suppressMotionAfterClick()
        let wasDragging = isSecondaryClickDragging
        isSecondaryClickDragging = false
        if wasDragging {
            controlSink.sendClick(Click(button: .right, action: .up, count: 1, modifiers: []))
        } else {
            controlSink.sendClick(Click(button: .right, action: .tap, count: 1, modifiers: []))
        }
    }

    // MARK: - Scroll strip (spec §4.1.5: "two-finger drag on the click area scrolls"; this
    // module's UI simplifies that UIKit-multitouch gesture to a dedicated single-finger scroll
    // strip — see the deviation note in `AirPointerScreen.swift`.)

    public func scrollChanged(translationY: Double) {
        if !isScrolling {
            isScrolling = true
            lastScrollTranslationY = 0
            controlSink.sendScrollPhase(ScrollPhase(phase: .began))
        }
        let delta = translationY - lastScrollTranslationY
        lastScrollTranslationY = translationY
        guard delta != 0 else { return }
        let timestamp = clock.now()
        Task { await motionSink.enqueueScroll(dx: 0, dy: delta, flags: [], source: .touch, timestamp: timestamp) }
    }

    public func scrollEnded(velocityY: Double) {
        guard isScrolling else { return }
        isScrolling = false
        lastScrollTranslationY = 0
        controlSink.sendScrollPhase(ScrollPhase(phase: .ended, vx: 0, vy: velocityY, momentum: true))
    }

    // MARK: - Orientation (spec §4.3.2)

    private var orientationToken: NSObjectProtocol?

    private func beginObservingOrientation() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        applyCurrentOrientation()
        orientationToken = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyCurrentOrientation() }
        }
    }

    private func endObservingOrientation() {
        if let orientationToken {
            NotificationCenter.default.removeObserver(orientationToken)
        }
        orientationToken = nil
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    private func applyCurrentOrientation() {
        guard !localSettings.isOrientationLocked else { return }
        engine.updateOrientation(currentInterfaceOrientation())
    }

    private func currentInterfaceOrientation() -> Orientation {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        switch scene?.interfaceOrientation {
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        case .portraitUpsideDown: return .upsideDown
        default: return .portrait
        }
    }
}
