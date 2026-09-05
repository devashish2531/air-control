// Features/AirMouse/AirMouseViewModel+Preview.swift
// Preview-only construction (arch §3.2: "every screen has a working #Preview without a network").
// `PreviewMotionSampler` never calls CoreMotion — Xcode's preview canvas / simulator gyro is
// unreliable — it just reports the device as gyro-capable and never delivers samples, which is
// enough to render every static state of the Air Mouse tab.
import Foundation

final class PreviewMotionSampler: MotionSampling {
    var isDeviceMotionAvailable: Bool = true
    var isActive: Bool = false

    func startUpdates(interval: TimeInterval, queue: OperationQueue, handler: @escaping @Sendable (MotionSampleData) -> Void) {
        isActive = true
    }

    func stopUpdates() {
        isActive = false
    }
}

extension AirMouseViewModel {
    @MainActor
    static func preview() -> AirMouseViewModel {
        let engine = GyroEngine(sampler: PreviewMotionSampler(), observeAppLifecycle: false)
        return AirMouseViewModel(
            engine: engine,
            localSettings: AirMouseLocalSettings(defaults: UserDefaults(suiteName: "AirMouseViewModel.preview")!),
            userSettings: UserSettings(defaults: UserDefaults(suiteName: "AirMouseViewModel.preview")!),
            haptics: UIKitHapticsService(supportsHaptics: false)
        )
    }
}
