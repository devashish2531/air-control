// Tests/TouchpadControllerTests.swift
// `TouchpadController`'s intent → sink mapping under different `UserSettings` (this agent's
// assignment: "controller mapping from intents to sink calls under different settings — natural
// scroll flip, tap-to-click off"). Exercises `process(_:timestamp:predicted:)` directly (the
// `async`, directly-awaitable seam) rather than the fire-and-forget `handle(_:timestamp:
// predicted:)` UIKit entry point.

import Testing
import Foundation
import AirControlFilters
import AirControlProtocol
@testable import Air_Control

private actor RecordingMotionEnqueuer: MotionEnqueuing {
    struct Call: Equatable {
        var dx: Double
        var dy: Double
        var flags: MotionFlags
        var source: MotionSource
        var timestamp: TimeInterval
        var isScroll: Bool
    }

    private(set) var calls: [Call] = []

    func enqueue(dx: Double, dy: Double, flags: MotionFlags, source: MotionSource, timestamp: TimeInterval) async {
        calls.append(Call(dx: dx, dy: dy, flags: flags, source: source, timestamp: timestamp, isScroll: false))
    }

    func enqueueScroll(dx: Double, dy: Double, flags: MotionFlags, source: MotionSource, timestamp: TimeInterval) async {
        calls.append(Call(dx: dx, dy: dy, flags: flags, source: source, timestamp: timestamp, isScroll: true))
    }
}

@MainActor
private final class RecordingControlMessageSink: ControlMessageSink {
    private(set) var clicks: [Click] = []
    private(set) var scrollPhases: [ScrollPhase] = []
    private(set) var settingsMessages: [Settings] = []

    func sendClick(_ click: Click) { clicks.append(click) }
    func sendScrollPhase(_ phase: ScrollPhase) { scrollPhases.append(phase) }
    func sendSettings(_ settings: Settings) { settingsMessages.append(settings) }
}

@MainActor
private final class RecordingHapticsService: HapticsService {
    var isHapticsEnabled: Bool = true
    var isSoundEnabled: Bool = true
    private(set) var firedEvents: [HapticEvent] = []

    func prepare(_ event: HapticEvent) {}
    func fire(_ event: HapticEvent) { firedEvents.append(event) }
}

@MainActor
@Suite struct TouchpadControllerTests {
    private func makeController() -> (TouchpadController, RecordingMotionEnqueuer, RecordingControlMessageSink, RecordingHapticsService, UserSettings) {
        let settings = UserSettings(defaults: UserDefaults(suiteName: "TouchpadControllerTests-\(UUID().uuidString)")!)
        let motion = RecordingMotionEnqueuer()
        let control = RecordingControlMessageSink()
        let haptics = RecordingHapticsService()
        let controller = TouchpadController(userSettings: settings, motion: motion, controlSink: control, haptics: haptics)
        return (controller, motion, control, haptics, settings)
    }

    @Test func moveIntentForwardsRawUnscaledDelta() async {
        let (controller, motion, _, _, settings) = makeController()
        settings.snapshot.pointer.sensitivity = 10 // must NOT scale the datagram (spec §4.2.4)

        await controller.process([.move(Delta(dx: 5, dy: -3))], timestamp: 1.0, predicted: false)

        let calls = await motion.calls
        #expect(calls.count == 1)
        #expect(calls[0].dx == 5)
        #expect(calls[0].dy == -3)
        #expect(calls[0].isScroll == false)
        #expect(calls[0].flags.isEmpty)
    }

    @Test func predictedMoveSetsPredictedFlag() async {
        let (controller, motion, _, _, _) = makeController()
        await controller.process([.move(Delta(dx: 1, dy: 1))], timestamp: 1.0, predicted: true)
        let calls = await motion.calls
        #expect(calls.count == 1)
        #expect(calls[0].flags.contains(.predicted))
    }

    @Test func naturalScrollOnlyAffectsTheSettingsMessageNotTheDeltaSign() async {
        let (controller, motion, control, _, settings) = makeController()
        settings.snapshot.gestures.naturalScroll = .natural

        controller.pushSettingsToHost()
        #expect(control.settingsMessages.last?.scrollDirection == .natural)

        // spec §3.6.4: the host inverts the sign for natural scroll — the client never does.
        await controller.process([.scrollChanged(Delta(dx: -5, dy: 2))], timestamp: 1.0, predicted: false)
        let calls = await motion.calls
        #expect(calls.count == 1)
        #expect(calls[0].dx == -5)
        #expect(calls[0].dy == 2)
        #expect(calls[0].isScroll == true)
    }

    @Test func invertedScrollDirectionSettingAlsoOnlyAffectsTheSettingsMessage() async {
        let (controller, _, control, _, settings) = makeController()
        settings.snapshot.gestures.naturalScroll = .inverted
        controller.pushSettingsToHost()
        #expect(control.settingsMessages.last?.scrollDirection == .inverted)
    }

    @Test func tapToClickOffSuppressesTapClicksButNotDownUp() async {
        let (controller, _, control, haptics, settings) = makeController()
        settings.snapshot.gestures.tapToClick = false

        await controller.process([.click(button: .left, kind: .tap, count: 1)], timestamp: 1.0, predicted: false)
        #expect(control.clicks.isEmpty)
        #expect(haptics.firedEvents.isEmpty)

        await controller.process([.click(button: .left, kind: .down, count: 1)], timestamp: 1.0, predicted: false)
        #expect(control.clicks.count == 1)
        #expect(control.clicks[0].action == .down)
    }

    @Test func tapToClickOnSendsTapClickAndHaptic() async {
        let (controller, _, control, haptics, settings) = makeController()
        settings.snapshot.gestures.tapToClick = true

        await controller.process([.click(button: .left, kind: .tap, count: 2)], timestamp: 1.0, predicted: false)

        #expect(control.clicks.count == 1)
        #expect(control.clicks[0].button == .left)
        #expect(control.clicks[0].action == .tap)
        #expect(control.clicks[0].count == 2)
        #expect(haptics.firedEvents == [.tapClick])
    }

    @Test func rightTapClickFiresSecondaryHaptic() async {
        let (controller, _, control, haptics, _) = makeController()
        await controller.process([.click(button: .right, kind: .tap, count: 1)], timestamp: 1.0, predicted: false)
        #expect(control.clicks[0].button == .right)
        #expect(haptics.firedEvents == [.secondaryClick])
    }

    @Test func dragLockSettingControlsGestureConfigTimeout() {
        let (controller, _, _, _, settings) = makeController()
        settings.snapshot.gestures.dragLock = false
        #expect(controller.gestureConfig.dragLockTimeout == nil)

        settings.snapshot.gestures.dragLock = true
        #expect(controller.gestureConfig.dragLockTimeout != nil)
    }

    @Test func momentumSettingControlsGestureConfig() {
        let (controller, _, _, _, settings) = makeController()
        settings.snapshot.gestures.momentum = false
        #expect(controller.gestureConfig.momentumEnabled == false)

        settings.snapshot.gestures.momentum = true
        #expect(controller.gestureConfig.momentumEnabled == true)
    }

    @Test func dragLockEngagedIntentUpdatesIndicatorAndFiresHaptic() async {
        let (controller, _, _, haptics, _) = makeController()
        await controller.process([.dragLockEngaged], timestamp: 1.0, predicted: false)
        #expect(controller.isDragLockEngaged == true)
        #expect(haptics.firedEvents == [.dragLockEngage])

        await controller.process([.dragLockDisengaged], timestamp: 1.0, predicted: false)
        #expect(controller.isDragLockEngaged == false)
        #expect(haptics.firedEvents == [.dragLockEngage, .dragLockRelease])
    }

    @Test func scrollPhaseBeganSendsMandatoryFlagAndControlMessage() async {
        let (controller, motion, control, _, _) = makeController()
        await controller.process([.scrollPhaseBegan], timestamp: 1.0, predicted: false)

        let calls = await motion.calls
        #expect(calls.count == 1)
        #expect(calls[0].flags.contains(.scrollBegan))
        #expect(calls[0].isScroll == true)
        #expect(control.scrollPhases.last?.phase == .began)
    }

    @Test func scrollPhaseEndedForwardsVelocityAndMomentum() async {
        let (controller, motion, control, _, _) = makeController()
        await controller.process(
            [.scrollPhaseEnded(velocity: Vector2(x: 100, y: -50), momentum: true)],
            timestamp: 1.0,
            predicted: false
        )
        let calls = await motion.calls
        #expect(calls.last?.flags.contains(.scrollEnded) == true)
        #expect(control.scrollPhases.last?.phase == .ended)
        #expect(control.scrollPhases.last?.vx == 100)
        #expect(control.scrollPhases.last?.vy == -50)
        #expect(control.scrollPhases.last?.momentum == true)
    }

    @Test func motionEndSendsMandatoryFlagWithZeroDelta() async {
        let (controller, motion, _, _, _) = makeController()
        await controller.process([.motionEnd], timestamp: 1.0, predicted: false)
        let calls = await motion.calls
        #expect(calls.count == 1)
        #expect(calls[0].dx == 0 && calls[0].dy == 0)
        #expect(calls[0].flags.contains(.motionEnd))
    }

    @Test func clickButtonStripSendsDownThenUp() {
        let (controller, _, control, haptics, _) = makeController()
        controller.clickButtonPressed(.left)
        controller.clickButtonReleased(.left)
        #expect(control.clicks.map(\.action) == [.down, .up])
        #expect(haptics.firedEvents == [.buttonDown, .buttonUp])
    }

    @Test func accelerationSettingMapsToWireEnum() {
        let (controller, _, control, _, settings) = makeController()
        settings.snapshot.pointer.acceleration = .standard
        controller.pushSettingsToHost()
        #expect(control.settingsMessages.last?.acceleration == .default)
    }

    // MARK: Scroll strip (owner UI request: right-edge vertical scroll strip, spec §4.2.5's
    // existing scroll intent path reused via `TouchpadController.processScrollStripChange/End` —
    // the directly-awaitable seam behind `scrollStripChanged/scrollStripEnded`'s `Task` hop).

    @Test func scrollStripChangeSendsBeganThenIncrementalDeltas() async {
        let (controller, motion, control, _, _) = makeController()

        await controller.processScrollStripChange(translationY: 10)
        await controller.processScrollStripChange(translationY: 25)

        let calls = await motion.calls
        #expect(calls.count == 3)
        #expect(calls[0].flags.contains(.scrollBegan))
        #expect(calls[0].dy == 0)
        #expect(calls[1].dy == 10) // 10 - 0
        #expect(calls[2].dy == 15) // 25 - 10
        #expect(calls[0].isScroll && calls[1].isScroll && calls[2].isScroll)
        #expect(control.scrollPhases.last?.phase == .began)
    }

    @Test func scrollStripEndSendsEndedWithVelocityAndConfiguredMomentum() async {
        let (controller, motion, control, _, settings) = makeController()
        settings.snapshot.gestures.momentum = true

        await controller.processScrollStripChange(translationY: 5)
        await controller.processScrollStripEnd(velocityY: -200)

        let calls = await motion.calls
        #expect(calls.last?.flags.contains(.scrollEnded) == true)
        #expect(control.scrollPhases.last?.phase == .ended)
        #expect(control.scrollPhases.last?.vx == 0)
        #expect(control.scrollPhases.last?.vy == -200)
        #expect(control.scrollPhases.last?.momentum == true)
    }

    @Test func scrollStripEndWithoutAPriorChangeIsANoOp() async {
        let (controller, motion, control, _, _) = makeController()
        await controller.processScrollStripEnd(velocityY: 42)
        let calls = await motion.calls
        #expect(calls.isEmpty)
        #expect(control.scrollPhases.isEmpty)
    }
}
