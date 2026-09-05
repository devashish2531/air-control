// Tests for clicks (spec §5.3.3) and scroll (spec §3.6, §5.3.4) — Services/EventInjector/
// EventInjector+Motion.swift.
import AirMouseFilters
import AppKit
import CoreGraphics
import Testing
@testable import Air_Mouse

@Suite struct EventInjectorClickScrollTests {
    private func makeInjector(clock: ManualClock = ManualClock()) -> (EventInjector, RecordingEventPoster) {
        let poster = RecordingEventPoster()
        let injector = EventInjector(
            poster: poster,
            clock: clock,
            pointerLocationProvider: { CGPoint(x: 500, y: 500) },
            startHeldInputWatchdog: false
        )
        return (injector, poster)
    }

    // MARK: - Clicks / click state

    @Test func tapSchedulesUpFifteenMillisecondsLater() async {
        let (injector, poster) = makeInjector()
        await injector.clickTap(button: .left, clickCount: 1)
        // The down posts synchronously; give the scheduled-up timer a chance to fire.
        try? await Task.sleep(nanoseconds: 60_000_000)
        #expect(poster.events.map(\.kind) == [.leftMouseDown, .leftMouseUp])
    }

    @Test func middleClickUsesOtherMouseWithButtonNumberTwo() async {
        let (injector, poster) = makeInjector()
        await injector.click(button: .middle, isDown: true, clickCount: 1)
        #expect(poster.lastEvent?.kind == .otherMouseDown)
        #expect(poster.lastEvent?.buttonNumber == 2)
    }

    @Test func secondClickWithinIntervalKeepsRequestedClickState() async {
        let clock = ManualClock()
        let (injector, poster) = makeInjector(clock: clock)
        await injector.click(button: .left, isDown: true, clickCount: 1)
        await injector.click(button: .left, isDown: false, clickCount: 1)
        clock.advance(by: 0.05) // well within doubleClickInterval
        await injector.click(button: .left, isDown: true, clickCount: 2)
        #expect(poster.lastEvent?.clickState == 2)
    }

    @Test func clickAfterLongIdleResetsClickStateToOne() async {
        let clock = ManualClock()
        let (injector, poster) = makeInjector(clock: clock)
        await injector.click(button: .left, isDown: true, clickCount: 1)
        await injector.click(button: .left, isDown: false, clickCount: 1)
        // spec §5.3.3: reset if the previous click was > 1.5x doubleClickIntervalMs ago.
        clock.advance(by: NSEvent.doubleClickInterval * 2)
        await injector.click(button: .left, isDown: true, clickCount: 2)
        #expect(poster.lastEvent?.clickState == 1)
    }

    // MARK: - Scroll phases / natural flip / horizontal

    @Test func scrollBeganPostsZeroDeltaWithBeganPhase() async {
        let (injector, poster) = makeInjector()
        await injector.scroll(phase: .began)
        let event = poster.lastEvent
        #expect(event?.kind == .scrollWheel)
        #expect(event?.scrollWheel1 == 0)
        #expect(event?.scrollWheel2 == 0)
        #expect(event?.scrollPhase == 1) // kCGScrollPhaseBegan
        #expect(event?.scrollIsContinuous == true)
    }

    @Test func changedAppliesGainAndRoutesAxesToWheel1And2() async {
        let (injector, poster) = makeInjector()
        await injector.updateScroll(speed: 5, invertForNatural: false) // gain ≈ 1.222
        await injector.scroll(phase: .began)
        await injector.scroll(phase: .changed, dx: 10, dy: 20)
        let event = poster.lastEvent
        #expect(event?.scrollPhase == 2) // kCGScrollPhaseChanged
        // wheel1 = vertical (dy), wheel2 = horizontal (dx) — spec §5.3.4.
        #expect(event?.scrollWheel1 == Int((20.0 * ScrollGain.gain(speed: 5)).rounded(.towardZero)))
        #expect(event?.scrollWheel2 == Int((10.0 * ScrollGain.gain(speed: 5)).rounded(.towardZero)))
    }

    @Test func naturalScrollFlipsSignOfBothAxes() async {
        let (injector, poster) = makeInjector()
        await injector.updateScroll(speed: 5, invertForNatural: true)
        await injector.scroll(phase: .began)
        await injector.scroll(phase: .changed, dx: 10, dy: 20)
        let event = poster.lastEvent
        #expect((event?.scrollWheel1 ?? 0) < 0)
        #expect((event?.scrollWheel2 ?? 0) < 0)
    }

    @Test func endedWithFastLiftStartsMomentum() async {
        let (injector, _) = makeInjector()
        await injector.scroll(phase: .began)
        await injector.scroll(
            phase: .ended,
            isMomentum: true,
            liftVelocity: Vector2(x: 0, y: 1000)
        )
        let engine = await injector.momentumEngine
        #expect(await engine.isActive)
    }

    @Test func endedBelowFlingThresholdDoesNotStartMomentum() async {
        let (injector, _) = makeInjector()
        await injector.scroll(phase: .began)
        await injector.scroll(phase: .ended, isMomentum: true, liftVelocity: Vector2(x: 0, y: 50))
        let engine = await injector.momentumEngine
        #expect(await !engine.isActive)
    }

    @Test func clientMomentumFalseSuppressesMomentumEvenAboveThreshold() async {
        let (injector, _) = makeInjector()
        await injector.scroll(phase: .began)
        await injector.scroll(phase: .ended, isMomentum: false, liftVelocity: Vector2(x: 0, y: 1000))
        let engine = await injector.momentumEngine
        #expect(await !engine.isActive)
    }

    @Test func cancelStopsActiveMomentum() async {
        let (injector, _) = makeInjector()
        await injector.scroll(phase: .began)
        await injector.scroll(phase: .ended, isMomentum: true, liftVelocity: Vector2(x: 0, y: 1000))
        let engine = await injector.momentumEngine
        #expect(await engine.isActive)

        await injector.scroll(phase: .cancel)
        #expect(await !engine.isActive)
    }
}
