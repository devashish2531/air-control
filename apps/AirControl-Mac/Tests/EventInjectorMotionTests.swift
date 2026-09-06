// Tests for EventInjector's motion path: Services/EventInjector/EventInjector+Motion.swift.
// spec §5.3.2 (pointer move), §5.3.8 (multi-display clamp), §5.4 (acceleration curve).
import AirControlFilters
import AirControlProtocol
import CoreGraphics
import Testing
@testable import Air_Control

@Suite struct EventInjectorMotionTests {
    /// Two adjacent displays with a deliberate 80 pt gap between them (spec §5.3.8's "gaps in
    /// L-shaped arrangements" case), so clamp-to-current-display behavior is exercised rather than
    /// "target already lies on some display".
    private static func twoDisplays(gap: Bool) -> DisplayTopologySnapshot {
        let main = DisplayInfo(id: 1, bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true)
        let secondaryX: CGFloat = gap ? 2000 : 1920
        let secondary = DisplayInfo(id: 2, bounds: CGRect(x: secondaryX, y: 0, width: 1920, height: 1080), isMain: false)
        return DisplayTopologySnapshot.make(from: [main, secondary])
    }

    private func makeInjector(
        start: CGPoint,
        displays: DisplayTopologySnapshot,
        clock: ManualClock = ManualClock()
    ) -> (EventInjector, RecordingEventPoster) {
        let poster = RecordingEventPoster()
        let injector = EventInjector(
            poster: poster,
            clock: clock,
            pointerLocationProvider: { start },
            displays: displays,
            startHeldInputWatchdog: false
        )
        return (injector, poster)
    }

    @Test func firstMotionOfBurstPostsMouseMovedWithAcceleratedIntegerDelta() async {
        let (injector, poster) = makeInjector(start: CGPoint(x: 100, y: 100), displays: Self.twoDisplays(gap: false))

        // spec §5.4: base(sensitivity: 5) == 1.39 (the doc's own worked example); first-of-burst
        // still applies `base`, only `accel(v)` is forced to 1 (spec: "first datagram of a burst
        // uses accel = 1"). 10 * 1.39 = 13.9 -> truncates to 13.
        await injector.applyMotion(dx: 10, dy: 0, source: .externalPointer, flags: [], sampleInterval: 0.008)

        let event = poster.lastEvent
        #expect(event?.kind == .mouseMoved)
        #expect(event?.deltaX == 13)
        #expect(event?.deltaY == 0)
        #expect(event?.location == CGPoint(x: 113, y: 100))
    }

    @Test func gyroSourceBypassesAccelerationEntirely() async {
        let (injector, poster) = makeInjector(start: CGPoint(x: 0, y: 0), displays: Self.twoDisplays(gap: false))

        // isFirstOfBurst would otherwise apply `base`; gyro must ignore both `base` and `accel`.
        await injector.applyMotion(dx: 10, dy: 4, source: .gyro, flags: [], sampleInterval: 0.008)

        let event = poster.lastEvent
        #expect(event?.deltaX == 10)
        #expect(event?.deltaY == 4)
    }

    @Test func zeroIntegerDeltaPostsNoEvent() async {
        let (injector, poster) = makeInjector(start: CGPoint(x: 0, y: 0), displays: Self.twoDisplays(gap: false))

        // Sub-pixel: 0.4 pt at gain 1 (gyro) truncates to 0 with everything held in the remainder.
        await injector.applyMotion(dx: 0.4, dy: 0, source: .gyro, flags: [], sampleInterval: 0.008)
        #expect(poster.events.isEmpty)
    }

    @Test func heldButtonProducesDraggedEventType() async {
        let (injector, poster) = makeInjector(start: CGPoint(x: 0, y: 0), displays: Self.twoDisplays(gap: false))

        await injector.click(button: .left, isDown: true, clickCount: 1)
        await injector.applyMotion(dx: 5, dy: 0, source: .gyro, flags: [], sampleInterval: 0.008)

        #expect(poster.lastEvent?.kind == .leftMouseDragged)
        #expect(poster.lastEvent?.buttonNumber == 0)
    }

    @Test func rightHeldButtonProducesRightDrag() async {
        let (injector, poster) = makeInjector(start: CGPoint(x: 0, y: 0), displays: Self.twoDisplays(gap: false))

        await injector.click(button: .right, isDown: true, clickCount: 1)
        await injector.applyMotion(dx: 5, dy: 0, source: .gyro, flags: [], sampleInterval: 0.008)

        #expect(poster.lastEvent?.kind == .rightMouseDragged)
    }

    @Test func targetInGapClampsToCurrentDisplayEdgeButKeepsRawDelta() async {
        let (injector, poster) = makeInjector(start: CGPoint(x: 1900, y: 500), displays: Self.twoDisplays(gap: true))

        // gyro ⇒ gain 1, so the raw integer delta is exactly 50; 1900 + 50 = 1950 lands in the 80 pt
        // gap between the two displays (1920...2000), which contains neither display.
        await injector.applyMotion(dx: 50, dy: 0, source: .gyro, flags: [], sampleInterval: 0.008)

        let event = poster.lastEvent
        #expect(event?.deltaX == 50, "raw ix is posted even though the cursor position is clamped")
        #expect(event?.location == CGPoint(x: 1920, y: 500), "clamped into the display containing the prior position")
    }

    @Test func targetInsideAnyDisplayIsAcceptedUnclamped() async {
        let (injector, poster) = makeInjector(start: CGPoint(x: 1900, y: 500), displays: Self.twoDisplays(gap: false))

        await injector.applyMotion(dx: 50, dy: 0, source: .gyro, flags: [], sampleInterval: 0.008)

        // No gap this time: 1950 lies inside the (adjacent) secondary display, so it is accepted as-is.
        #expect(poster.lastEvent?.location == CGPoint(x: 1950, y: 500))
    }

    @Test func motionEndFlagZeroesRemainderAndPostsNothing() async {
        let (injector, poster) = makeInjector(start: CGPoint(x: 0, y: 0), displays: Self.twoDisplays(gap: false))

        // Build up a nonzero remainder first (0.4 pt, gyro gain 1, below the 1-pixel threshold).
        await injector.applyMotion(dx: 0.4, dy: 0, source: .gyro, flags: [], sampleInterval: 0.008)
        await injector.applyMotion(dx: 0, dy: 0, source: .gyro, flags: [.motionEnd], sampleInterval: 0.008)
        #expect(poster.events.isEmpty)

        // If the remainder had survived, this delta would combine with the stale 0.4 to reach 1 full
        // pixel; since motionEnd must have zeroed it, 0.4 + 0.4 stays under 1 and still posts nothing.
        await injector.applyMotion(dx: 0.4, dy: 0, source: .gyro, flags: [], sampleInterval: 0.008)
        #expect(poster.events.isEmpty)
    }

    @Test func recenterJumpsToDisplayCenterContainingCurrentPosition() async {
        let (injector, poster) = makeInjector(start: CGPoint(x: 100, y: 100), displays: Self.twoDisplays(gap: false))
        await injector.recenter()
        #expect(poster.lastEvent?.kind == .mouseMoved)
        #expect(poster.lastEvent?.location == CGPoint(x: 960, y: 540))
    }
}
