// Tests/GyroClutchTests.swift
// Clutch hold-vs-toggle logic, double-tap → recenter debounce, and click motion suppression
// (spec §4.3.6).
import AirControlFilters
import Foundation
import Testing
@testable import Air_Control

@MainActor
@Suite struct GyroClutchTests {
    private func makeEngine(clutchMode: ClutchMode = .hold) -> (GyroEngine, FakeMotionSampler, ManualClock) {
        let sampler = FakeMotionSampler()
        let clock = ManualClock(start: 0)
        let engine = GyroEngine(
            sampler: sampler,
            clock: clock,
            settings: GyroEngineSettings(clutchMode: clutchMode),
            observeAppLifecycle: false
        )
        return (engine, sampler, clock)
    }

    @Test func holdModeEngagesOnPressAndDisengagesOnRelease() async {
        let (engine, _, _) = makeEngine(clutchMode: .hold)
        await engine.start()
        #expect(engine.clutchMode == .hold)

        engine.clutchPressBegan()
        #expect(await waitUntil { engine.state == .armed })

        engine.clutchPressEnded()
        #expect(await waitUntil { engine.state == .idle })
    }

    @Test func holdModePressBeganAloneDoesNothingUntilReleased() async {
        let (engine, _, _) = makeEngine(clutchMode: .hold)
        await engine.start()
        engine.clutchPressBegan()
        #expect(await waitUntil { engine.state == .armed })
        // Still held down — no press-ended yet — should remain armed, not bounce back to idle.
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(engine.state == .armed)
    }

    @Test func toggleModePressBeganAloneDoesNothing() async {
        let (engine, _, _) = makeEngine(clutchMode: .toggle)
        await engine.start()
        engine.clutchPressBegan() // toggle mode: press-down is a no-op
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(engine.state == .idle)
    }

    @Test func toggleModeTogglesOnEachTap() async {
        let (engine, _, _) = makeEngine(clutchMode: .toggle)
        await engine.start()

        engine.clutchPressEnded() // tap 1: engage
        #expect(await waitUntil { engine.state == .armed })

        engine.clutchPressEnded() // tap 2: disengage
        #expect(await waitUntil { engine.state == .idle })
    }

    @Test func doubleTapWithinWindowRecenters() async {
        let (engine, _, clock) = makeEngine(clutchMode: .hold)
        await engine.start()

        clock.set(0)
        engine.clutchPressBegan()
        engine.clutchPressEnded()
        #expect(await waitUntil { engine.state == .idle })
        #expect(engine.recenterCallCount == 0)

        clock.set(0.1) // within the 300 ms double-tap window
        engine.clutchPressBegan()
        engine.clutchPressEnded()
        #expect(await waitUntil { engine.state == .idle })
        #expect(engine.recenterCallCount == 1)
    }

    @Test func tapsOutsideWindowDoNotRecenter() async {
        let (engine, _, clock) = makeEngine(clutchMode: .hold)
        await engine.start()

        clock.set(0)
        engine.clutchPressBegan()
        engine.clutchPressEnded()
        #expect(await waitUntil { engine.state == .idle })

        clock.set(1.0) // well outside the 300 ms window
        engine.clutchPressBegan()
        engine.clutchPressEnded()
        #expect(await waitUntil { engine.state == .idle })
        #expect(engine.recenterCallCount == 0)
    }

    @Test func recenterModeGatesDoubleTap() async {
        let sampler = FakeMotionSampler()
        let clock = ManualClock(start: 0)
        let engine = GyroEngine(
            sampler: sampler,
            clock: clock,
            settings: GyroEngineSettings(clutchMode: .hold, recenterMode: .shake),
            observeAppLifecycle: false
        )
        await engine.start()

        clock.set(0)
        engine.clutchPressBegan()
        engine.clutchPressEnded()
        clock.set(0.05)
        engine.clutchPressBegan()
        engine.clutchPressEnded()
        #expect(await waitUntil { engine.state == .idle })
        #expect(engine.recenterCallCount == 0) // double-tap disabled when recenterMode == .shake
    }

    @Test func shakeGestureRecentersWhenEnabledAndDebounces() async {
        let sampler = FakeMotionSampler()
        let clock = ManualClock(start: 0)
        let engine = GyroEngine(
            sampler: sampler,
            clock: clock,
            settings: GyroEngineSettings(recenterMode: .shake),
            observeAppLifecycle: false
        )
        clock.set(0)
        engine.handleShakeGesture()
        #expect(engine.recenterCallCount == 1)

        clock.set(0.5) // within the 1 s debounce
        engine.handleShakeGesture()
        #expect(engine.recenterCallCount == 1)

        clock.set(1.1) // past the debounce
        engine.handleShakeGesture()
        #expect(engine.recenterCallCount == 2)
    }
}
