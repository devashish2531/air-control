// Features/AirPointer/AirPointerFeature.swift
// Factory that wires a `GyroEngine` + `AirPointerViewModel` from `AppEnvironment` (arch §3.2:
// "View models are constructed by the views from the environment and never construct services
// themselves" — this is that construction step for the Air Pointer tab).
//
// Integration note (can't be fixed from within this assignment's owned paths): `AppEnvironment`'s
// `gyro` slot defaults to `NoOpGyroEngine` (`App/DefaultServices.swift`), which always reports
// `isGyroAvailable == false`, and `RootTabView` (`App/RootTabView.swift`, not owned by this
// assignment) hides the Air Pointer tab whenever that's false — computed once per render, before
// this screen ever gets a chance to run and swap in the real `GyroEngine`. For the tab to appear
// on a real device, whoever constructs `AppEnvironment` in `AirControlApp.swift` should pass a real
// `GyroEngine` at startup, e.g. `AppEnvironment(gyro: GyroEngine())`. Once that happens,
// `AirPointerFeature.make(environment:)` below detects and reuses that same instance rather than
// creating a second one.
//
// Similarly, `environment.motion` (`any MotionPublishing`) defaults to `NoOpMotionPublisher`,
// which does not conform to the Motion agent's `MotionEnqueuing` (Services/MotionPublisher/
// MotionEnqueuing.swift) — only a real `MotionPublisher` does. This factory casts opportunistically
// (`environment.motion as? MotionEnqueuing`) so once whoever wires `environment.motion =
// MotionPublisher(...)` at startup, `GyroEngine` and this view model's scroll-delta path start
// flowing through the real pipeline with no change here. There is no environment slot at all yet
// for the Touchpad agent's `ControlMessageSink` (clicks/scroll-phase) — this factory defaults to
// `NoOpControlMessageSink()`; wire the real Connection-backed adapter through here once one exists
// (mirrors the exact gap `TouchpadFeature.make(environment:motion:controlSink:)` notes for itself).
import Foundation
import SwiftUI

public enum AirPointerFeature {
    @MainActor
    public static func make(environment: AppEnvironment) -> AirPointerScreen {
        AirPointerScreen(viewModel: makeViewModel(environment: environment))
    }

    @MainActor
    public static func makeViewModel(
        environment: AppEnvironment,
        controlSink: any ControlMessageSink = NoOpControlMessageSink()
    ) -> AirPointerViewModel {
        let localSettings = AirPointerLocalSettings()
        let motionSink = (environment.motion as? MotionEnqueuing) ?? NoOpMotionEnqueuer()
        let engine: GyroEngine
        if let existing = environment.gyro as? GyroEngine {
            engine = existing
        } else {
            let gyro = environment.userSettings.snapshot.gyro
            engine = GyroEngine(
                sink: motionSink,
                settings: GyroEngineSettings(
                    sensitivity: Double(gyro.sensitivity),
                    smoothingSlider: Double(gyro.smoothing),
                    deadZoneDegPerSec: gyro.deadZoneDegreesPerSecond,
                    clutchMode: localSettings.clutchMode,
                    recenterMode: localSettings.recenterMode,
                    isOrientationLocked: localSettings.isOrientationLocked
                )
            )
            environment.gyro = engine
        }
        return AirPointerViewModel(
            engine: engine,
            localSettings: localSettings,
            userSettings: environment.userSettings,
            haptics: environment.haptics,
            controlSink: controlSink,
            motionSink: motionSink
        )
    }
}
