// Tests for pause/resume + release-all (spec §5.3.10, §5.3.11) and the held-input watchdog
// (spec §5.3.11 / §11.3 "Held-input watchdog: 60 s").
import AirControlFilters
import AirControlProtocol
import Testing
@testable import Air_Control

@Suite struct EventInjectorPauseAndWatchdogTests {
    private func makeInjector(clock: ManualClock = ManualClock()) -> (EventInjector, RecordingEventPoster) {
        let poster = RecordingEventPoster()
        let injector = EventInjector(poster: poster, clock: clock, startHeldInputWatchdog: false)
        return (injector, poster)
    }

    @Test func pauseReleasesHeldButtonAndLatchedModifier() async {
        let (injector, poster) = makeInjector()
        await injector.click(button: .left, isDown: true, clickCount: 1)
        await injector.setModifiers([.command])
        poster.removeAll()

        await injector.pause()

        #expect(poster.events.contains { $0.kind == .leftMouseUp })
        #expect(poster.events.contains { $0.kind == .keyUp && $0.keycode == Int(VirtualKey.kVK_Command) })
        #expect(await injector.heldButtons.isEmpty)
        #expect(await injector.latchedModifiers.isEmpty)
    }

    @Test func pausedInjectorDropsSubsequentInput() async {
        let (injector, poster) = makeInjector()
        await injector.pause()
        poster.removeAll()

        await injector.applyMotion(dx: 100, dy: 100, source: .externalPointer, flags: [], sampleInterval: 0.01)
        await injector.click(button: .left, isDown: true, clickCount: 1)

        #expect(poster.events.isEmpty)
        let counters = await injector.snapshotCounters()
        #expect(counters.droppedWhilePaused == 2)
    }

    @Test func resumeAllowsInputAgain() async {
        let (injector, poster) = makeInjector()
        await injector.pause()
        await injector.resume()
        await injector.click(button: .left, isDown: true, clickCount: 1)
        #expect(poster.events.contains { $0.kind == .leftMouseDown })
    }

    @Test func heldInputWatchdogReleasesAfterThresholdIdle() async {
        let clock = ManualClock()
        let (injector, poster) = makeInjector(clock: clock)
        await injector.click(button: .left, isDown: true, clickCount: 1)
        poster.removeAll()

        clock.advance(by: HeldInputLedger.testStaleThreshold + 1)
        await injector.checkHeldInputWatchdog(threshold: HeldInputLedger.testStaleThreshold)
        // the watchdog releases via an unstructured Task; give it a moment to run.
        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(poster.events.contains { $0.kind == .leftMouseUp })
        #expect(await injector.heldButtons.isEmpty)
    }

    @Test func heldInputWatchdogDoesNothingBeforeThreshold() async {
        let clock = ManualClock()
        let (injector, poster) = makeInjector(clock: clock)
        await injector.click(button: .left, isDown: true, clickCount: 1)
        poster.removeAll()

        clock.advance(by: HeldInputLedger.testStaleThreshold - 0.5)
        await injector.checkHeldInputWatchdog(threshold: HeldInputLedger.testStaleThreshold)
        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(poster.events.isEmpty)
        #expect(await injector.heldButtons.contains(.left))
    }

    @Test func activityResetsTheWatchdogClock() async {
        let clock = ManualClock()
        let (injector, poster) = makeInjector(clock: clock)
        await injector.click(button: .left, isDown: true, clickCount: 1)
        clock.advance(by: HeldInputLedger.testStaleThreshold - 0.1)
        // Any further activity (e.g. another click) resets the idle clock.
        await injector.click(button: .right, isDown: true, clickCount: 1)
        poster.removeAll()

        clock.advance(by: HeldInputLedger.testStaleThreshold - 0.1)
        await injector.checkHeldInputWatchdog(threshold: HeldInputLedger.testStaleThreshold)
        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(poster.events.isEmpty, "activity within the threshold must postpone the release")
    }
}
