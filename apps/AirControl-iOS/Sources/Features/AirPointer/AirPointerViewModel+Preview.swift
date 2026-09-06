// Features/AirPointer/AirPointerViewModel+Preview.swift
// Preview-only construction (arch §3.2: "every screen has a working #Preview without a network").
// `PreviewMotionSampler` never calls CoreMotion — Xcode's preview canvas / simulator gyro is
// unreliable — it just reports the device as gyro-capable and never delivers samples, which is
// enough to render every static state of the Air Pointer tab.
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

extension AirPointerViewModel {
    @MainActor
    static func preview() -> AirPointerViewModel {
        let engine = GyroEngine(sampler: PreviewMotionSampler(), observeAppLifecycle: false)
        return AirPointerViewModel(
            engine: engine,
            localSettings: AirPointerLocalSettings(defaults: UserDefaults(suiteName: "AirPointerViewModel.preview")!),
            userSettings: UserSettings(defaults: UserDefaults(suiteName: "AirPointerViewModel.preview")!),
            haptics: UIKitHapticsService(supportsHaptics: false)
        )
    }
}
