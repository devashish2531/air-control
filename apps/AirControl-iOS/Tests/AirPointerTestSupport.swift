// Tests/AirPointerTestSupport.swift
// Fakes for `AirPointerViewModel` feature tests: a recording `HapticsService`,
// `ControlMessageSink` (Features/Touchpad, another agent's protocol — reused rather than
// duplicated, see `AirPointerViewModel.swift`), and `MotionEnqueuing` sink for scroll deltas.
import AirControlFilters
import AirControlProtocol
import Foundation
@testable import Air_Control

@MainActor
final class FakeHapticsService: HapticsService {
    var isHapticsEnabled: Bool = true
    var isSoundEnabled: Bool = true
    private(set) var preparedEvents: [HapticEvent] = []
    private(set) var firedEvents: [HapticEvent] = []

    func prepare(_ event: HapticEvent) { preparedEvents.append(event) }
    func fire(_ event: HapticEvent) { firedEvents.append(event) }
}

@MainActor
final class FakeControlMessageSink: ControlMessageSink {
    private(set) var clicks: [Click] = []
    private(set) var scrollPhases: [ScrollPhase] = []

    func sendClick(_ click: Click) { clicks.append(click) }
    func sendScrollPhase(_ phase: ScrollPhase) { scrollPhases.append(phase) }
    func sendSettings(_ settings: Settings) {}

    func waitForClickCount(_ count: Int, timeout: TimeInterval = 2.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while clicks.count < count, Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return clicks.count >= count
    }
}

actor FakeMotionEnqueuer: MotionEnqueuing {
    private(set) var moveDeltas: [(x: Double, y: Double)] = []
    private(set) var scrollDeltas: [(x: Double, y: Double)] = []

    func enqueue(dx: Double, dy: Double, flags: MotionFlags, source: MotionSource, timestamp: TimeInterval) {
        moveDeltas.append((dx, dy))
    }

    func enqueueScroll(dx: Double, dy: Double, flags: MotionFlags, source: MotionSource, timestamp: TimeInterval) {
        scrollDeltas.append((dx, dy))
    }
}

@MainActor
func makeAirPointerViewModel(
    clutchMode: ClutchMode = .hold,
    haptics: FakeHapticsService = FakeHapticsService(),
    controlSink: FakeControlMessageSink = FakeControlMessageSink(),
    motionSink: FakeMotionEnqueuer = FakeMotionEnqueuer()
) -> AirPointerViewModel {
    let suite = "AirPointerViewModelTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let userSettings = UserSettings(defaults: defaults)
    let localSettings = AirPointerLocalSettings(defaults: defaults)
    localSettings.clutchMode = clutchMode
    let engine = GyroEngine(
        sampler: FakeMotionSampler(),
        settings: GyroEngineSettings(clutchMode: clutchMode),
        observeAppLifecycle: false
    )
    return AirPointerViewModel(
        engine: engine,
        localSettings: localSettings,
        userSettings: userSettings,
        haptics: haptics,
        controlSink: controlSink,
        motionSink: motionSink
    )
}
