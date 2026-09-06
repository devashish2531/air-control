import Testing
import Foundation
@testable import AirControlFilters

private func sample(
    _ id: Int, _ phase: TouchPhase, _ pos: Point, _ t: TimeInterval, radius: Double = 0
) -> TouchSample {
    TouchSample(id: TouchID(id), phase: phase, position: pos, timestamp: t, majorRadius: radius)
}

private func hasClick(_ events: [TouchpadIntent]) -> Bool {
    events.contains { if case .click = $0 { return true }; return false }
}

private func hasMove(_ events: [TouchpadIntent]) -> Bool {
    events.contains { if case .move = $0 { return true }; return false }
}

@Suite struct GestureRecognizerTests {
    // MARK: Tap / double-tap / triple-tap

    @Test func singleTapEmitsLeftClickCountOne() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, .zero, 0)])
        events += rec.handle([sample(1, .ended, Point(x: 1, y: 1), 0.05)])
        #expect(events.contains(.click(button: .left, kind: .tap, count: 1)))
    }

    @Test func doubleTapViaDragArmedPathIncrementsCount() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, .zero, 0)])
        events += rec.handle([sample(1, .ended, .zero, 0.05)])
        events += rec.handle([sample(2, .began, .zero, 0.10)]) // within tapAndDragWindow -> dragArmed
        events += rec.handle([sample(2, .ended, .zero, 0.15)]) // lifted quickly without moving -> tap #2
        #expect(events.contains(.click(button: .left, kind: .tap, count: 2)))
    }

    @Test func doubleTapWithTapAndDragDisabledGoesThroughFreshTouch1() {
        var config = GestureConfig()
        config.tapAndDragEnabled = false
        var rec = GestureRecognizer(config: config)
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, .zero, 0)])
        events += rec.handle([sample(1, .ended, .zero, 0.05)])
        events += rec.handle([sample(2, .began, .zero, 0.10)])
        events += rec.handle([sample(2, .ended, .zero, 0.15)])
        #expect(events.contains(.click(button: .left, kind: .tap, count: 2)))
    }

    @Test func tripleTapCapsAtThree() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        var id = 1
        var t = 0.0
        for _ in 0..<4 { // a 4th tap should still report count 3, not 4 or reset to 1
            events += rec.handle([sample(id, .began, .zero, t)])
            events += rec.handle([sample(id, .ended, .zero, t + 0.02)])
            t += 0.05
            id += 1
        }
        let counts = events.compactMap { intent -> Int? in
            if case let .click(.left, .tap, count) = intent { return count }
            return nil
        }
        #expect(counts == [1, 2, 3, 3])
    }

    @Test func doubleTapOutsideIntervalResetsCount() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, .zero, 0)])
        events += rec.handle([sample(1, .ended, .zero, 0.05)])
        // tapAndDragWindow (300ms) closes first via advanceTime, so the second tap starts fresh.
        _ = rec.advanceTime(to: 1.0)
        events += rec.handle([sample(2, .began, .zero, 1.0)])
        events += rec.handle([sample(2, .ended, .zero, 1.05)])
        let counts = events.compactMap { intent -> Int? in
            if case let .click(.left, .tap, count) = intent { return count }
            return nil
        }
        #expect(counts == [1, 1])
    }

    @Test func doubleTapOutsideMovementResetsCount() {
        var config = GestureConfig()
        config.tapAndDragEnabled = false
        var rec = GestureRecognizer(config: config)
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, .zero, 0)])
        events += rec.handle([sample(1, .ended, .zero, 0.05)])
        events += rec.handle([sample(2, .began, Point(x: 100, y: 100), 0.10)]) // far away
        events += rec.handle([sample(2, .ended, Point(x: 100, y: 100), 0.15)])
        let counts = events.compactMap { intent -> Int? in
            if case let .click(.left, .tap, count) = intent { return count }
            return nil
        }
        #expect(counts == [1, 1])
    }

    @Test func tapExactlyAtMaxDurationBoundaryQualifies() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, .zero, 0)])
        events += rec.handle([sample(1, .ended, .zero, 0.200)])
        #expect(events.contains(.click(button: .left, kind: .tap, count: 1)))
    }

    @Test func tapJustOverMaxDurationDoesNotQualify() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, .zero, 0)])
        events += rec.handle([sample(1, .ended, .zero, 0.201)])
        #expect(!hasClick(events))
        #expect(events.contains(.motionEnd))
    }

    @Test func tapMovementExactlyAtBoundaryQualifies() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, .zero, 0)])
        events += rec.handle([sample(1, .moved, Point(x: 8, y: 0), 0.05)])
        events += rec.handle([sample(1, .ended, Point(x: 8, y: 0), 0.1)])
        #expect(events.contains(.click(button: .left, kind: .tap, count: 1)))
    }

    @Test func movementBeyondTapThresholdCancelsTap() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, .zero, 0)])
        events += rec.handle([sample(1, .moved, Point(x: 20, y: 0), 0.05)])
        events += rec.handle([sample(1, .ended, Point(x: 20, y: 0), 0.1)])
        #expect(!hasClick(events))
        #expect(events.contains(.motionEnd))
    }

    @Test func cancelledTouchEmitsMotionEndNoClick() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, .zero, 0)])
        events += rec.handle([sample(1, .cancelled, .zero, 0.05)])
        #expect(events.contains(.motionEnd))
        #expect(!hasClick(events))
    }

    // MARK: Tap-and-drag / drag-lock

    @Test func tapAndDragEntersDraggingOnMovementWithinWindow() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, .zero, 0)])
        events += rec.handle([sample(1, .ended, .zero, 0.05)])
        events += rec.handle([sample(2, .began, .zero, 0.10)])
        events += rec.handle([sample(2, .moved, Point(x: 20, y: 0), 0.12)])
        #expect(events.contains(.click(button: .left, kind: .down, count: 1)))
        #expect(hasMove(events))
    }

    @Test func dragEndsWithClickUpWhenDragLockDisabled() {
        var config = GestureConfig()
        config.dragLockTimeout = nil
        var rec = GestureRecognizer(config: config)
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, .zero, 0)])
        events += rec.handle([sample(1, .ended, .zero, 0.05)])
        events += rec.handle([sample(2, .began, .zero, 0.10)])
        events += rec.handle([sample(2, .moved, Point(x: 20, y: 0), 0.12)])
        events += rec.handle([sample(2, .ended, Point(x: 20, y: 0), 0.20)])
        #expect(events.contains(.click(button: .left, kind: .up, count: 1)))
        #expect(events.contains(.motionEnd))
    }

    @Test func dragEndsEntersDragLockedWhenEnabled() {
        var rec = GestureRecognizer() // default dragLockTimeout = 3s
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, .zero, 0)])
        events += rec.handle([sample(1, .ended, .zero, 0.05)])
        events += rec.handle([sample(2, .began, .zero, 0.10)])
        events += rec.handle([sample(2, .moved, Point(x: 20, y: 0), 0.12)])
        events += rec.handle([sample(2, .ended, Point(x: 20, y: 0), 0.20)])
        #expect(events.contains(.dragLockEngaged))
        #expect(!events.contains(.click(button: .left, kind: .up, count: 1)))
    }

    @Test func dragLockReleasedBySingleTap() {
        var rec = GestureRecognizer()
        _ = rec.handle([sample(1, .began, .zero, 0)])
        _ = rec.handle([sample(1, .ended, .zero, 0.05)])
        _ = rec.handle([sample(2, .began, .zero, 0.10)])
        _ = rec.handle([sample(2, .moved, Point(x: 20, y: 0), 0.12)])
        _ = rec.handle([sample(2, .ended, Point(x: 20, y: 0), 0.20)]) // now drag-locked

        var events: [TouchpadIntent] = []
        events += rec.handle([sample(3, .began, Point(x: 20, y: 0), 0.5)])
        events += rec.handle([sample(3, .ended, Point(x: 20, y: 0), 0.55)])
        #expect(events.contains(.click(button: .left, kind: .up, count: 1)))
        #expect(events.contains(.dragLockDisengaged))
    }

    @Test func dragLockReleasedByTimeout() {
        var rec = GestureRecognizer()
        _ = rec.handle([sample(1, .began, .zero, 0)])
        _ = rec.handle([sample(1, .ended, .zero, 0.05)])
        _ = rec.handle([sample(2, .began, .zero, 0.10)])
        _ = rec.handle([sample(2, .moved, Point(x: 20, y: 0), 0.12)])
        _ = rec.handle([sample(2, .ended, Point(x: 20, y: 0), 0.20)]) // deadline = 0.20 + 3.0

        let events = rec.advanceTime(to: 3.3)
        #expect(events.contains(.click(button: .left, kind: .up, count: 1)))
        #expect(events.contains(.dragLockDisengaged))
    }

    @Test func dragLockDoesNotTimeOutBeforeDeadline() {
        var rec = GestureRecognizer()
        _ = rec.handle([sample(1, .began, .zero, 0)])
        _ = rec.handle([sample(1, .ended, .zero, 0.05)])
        _ = rec.handle([sample(2, .began, .zero, 0.10)])
        _ = rec.handle([sample(2, .moved, Point(x: 20, y: 0), 0.12)])
        _ = rec.handle([sample(2, .ended, Point(x: 20, y: 0), 0.20)])

        let events = rec.advanceTime(to: 3.0) // just under the 3.2s deadline
        #expect(events.isEmpty)
    }

    @Test func dragLockResumesOnFingerDownAndMove() {
        var rec = GestureRecognizer()
        _ = rec.handle([sample(1, .began, .zero, 0)])
        _ = rec.handle([sample(1, .ended, .zero, 0.05)])
        _ = rec.handle([sample(2, .began, .zero, 0.10)])
        _ = rec.handle([sample(2, .moved, Point(x: 20, y: 0), 0.12)])
        _ = rec.handle([sample(2, .ended, Point(x: 20, y: 0), 0.20)])

        var events: [TouchpadIntent] = []
        events += rec.handle([sample(3, .began, Point(x: 20, y: 0), 0.5)])
        events += rec.handle([sample(3, .moved, Point(x: 40, y: 0), 0.52)])
        #expect(hasMove(events))
        #expect(!events.contains(.click(button: .left, kind: .up, count: 1)))
    }

    @Test func tapAndDragWindowClosingMeansNextTouchIsFreshNotArmed() {
        var rec = GestureRecognizer()
        _ = rec.handle([sample(1, .began, .zero, 0)])
        _ = rec.handle([sample(1, .ended, .zero, 0.05)])
        _ = rec.advanceTime(to: 0.5) // tap-and-drag window (300ms) elapsed

        var events: [TouchpadIntent] = []
        events += rec.handle([sample(2, .began, Point(x: 0, y: 0), 0.5)])
        events += rec.handle([sample(2, .moved, Point(x: 20, y: 0), 0.52)])
        #expect(!events.contains { if case .click(_, .down, _) = $0 { return true }; return false })
    }

    @Test func tapCountResetsAfterInterveningDrag() {
        var rec = GestureRecognizer()
        _ = rec.handle([sample(1, .began, .zero, 0)])
        _ = rec.handle([sample(1, .ended, .zero, 0.05)]) // tap #1

        _ = rec.handle([sample(2, .began, .zero, 0.06)]) // dragArmed
        _ = rec.handle([sample(2, .moved, Point(x: 20, y: 0), 0.08)]) // dragging
        _ = rec.handle([sample(2, .ended, Point(x: 20, y: 0), 0.5)]) // drag-locked
        _ = rec.advanceTime(to: 4.0) // lock times out, back to idle

        var events: [TouchpadIntent] = []
        events += rec.handle([sample(3, .began, Point(x: 100, y: 100), 5.0)])
        events += rec.handle([sample(3, .ended, Point(x: 100, y: 100), 5.05)])
        #expect(events.contains(.click(button: .left, kind: .tap, count: 1)))
    }

    // MARK: Long press

    @Test func longPressEmitsRightClickWhenEnabled() {
        var config = GestureConfig()
        config.longPressRightClickEnabled = true
        var rec = GestureRecognizer(config: config)
        _ = rec.handle([sample(1, .began, .zero, 0)])
        let events = rec.advanceTime(to: 0.5)
        #expect(events.contains(.click(button: .right, kind: .tap, count: 1)))
        #expect(events.contains(.longPressHaptic))
    }

    @Test func longPressDisabledByDefaultProducesNothing() {
        var rec = GestureRecognizer()
        _ = rec.handle([sample(1, .began, .zero, 0)])
        let events = rec.advanceTime(to: 0.5)
        #expect(events.isEmpty)
    }

    @Test func longPressDoesNotFireBeforeDuration() {
        var config = GestureConfig()
        config.longPressRightClickEnabled = true
        var rec = GestureRecognizer(config: config)
        _ = rec.handle([sample(1, .began, .zero, 0)])
        let events = rec.advanceTime(to: 0.4)
        #expect(events.isEmpty)
    }

    // MARK: Motion suppression / finger-count settle

    @Test func motionSuppressedRightAfterTapThenResumes() {
        var config = GestureConfig()
        config.tapAndDragEnabled = false
        var rec = GestureRecognizer(config: config)
        _ = rec.handle([sample(1, .began, .zero, 0)])
        _ = rec.handle([sample(1, .ended, .zero, 0.05)]) // suppress until 0.13

        let suppressed = rec.handle([sample(2, .began, .zero, 0.06)])
            + rec.handle([sample(2, .moved, Point(x: 20, y: 0), 0.10)])
        #expect(!hasMove(suppressed))

        let resumed = rec.handle([sample(2, .moved, Point(x: 40, y: 0), 0.20)])
        #expect(hasMove(resumed))
    }

    @Test func fingerCountSettleSuppressesEarlyTinyMove() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, .zero, 0)])
        events += rec.handle([sample(1, .moved, Point(x: 1, y: 0), 0.02)])
        #expect(!hasMove(events))

        let events2 = rec.handle([sample(1, .moved, Point(x: 2, y: 0), 0.09)])
        #expect(hasMove(events2))
    }

    // MARK: Multi-finger

    @Test func secondFingerDuringTouch1EscalatesAndCancelsSingleTap() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, Point(x: 0, y: 0), 0)])
        events += rec.handle([sample(2, .began, Point(x: 10, y: 0), 0.05)])
        events += rec.handle([sample(1, .ended, Point(x: 0, y: 0), 0.1), sample(2, .ended, Point(x: 10, y: 0), 0.1)])
        #expect(events.contains(.click(button: .right, kind: .tap, count: 1)))
        #expect(!events.contains { if case .click(.left, _, _) = $0 { return true }; return false })
    }

    @Test func twoFingerTapEmitsRightClick() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, Point(x: 0, y: 0), 0)])
        events += rec.handle([sample(2, .began, Point(x: 10, y: 0), 0.01)])
        events += rec.handle([sample(1, .ended, Point(x: 0, y: 0), 0.05), sample(2, .ended, Point(x: 10, y: 0), 0.05)])
        #expect(events.contains(.click(button: .right, kind: .tap, count: 1)))
    }

    @Test func twoFingerScrollEmitsBeganChangedEnded() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, Point(x: 0, y: 0), 0)])
        events += rec.handle([sample(2, .began, Point(x: 10, y: 0), 0.01)])

        var t = 0.05
        for i in 1...5 {
            let dy = Double(i) * 10.0
            events += rec.handle([sample(1, .moved, Point(x: 0, y: dy), t), sample(2, .moved, Point(x: 10, y: dy), t)])
            t += 1.0 / 60.0
        }
        events += rec.handle([sample(1, .ended, Point(x: 0, y: 50), t), sample(2, .ended, Point(x: 10, y: 50), t)])

        #expect(events.contains(.scrollPhaseBegan))
        #expect(events.contains { if case .scrollChanged = $0 { return true }; return false })
        #expect(events.contains { if case .scrollPhaseEnded = $0 { return true }; return false })
    }

    @Test func scrollEndedVelocityIsNonZeroForASustainedFling() {
        var rec = GestureRecognizer()
        _ = rec.handle([sample(1, .began, Point(x: 0, y: 0), 0)])
        _ = rec.handle([sample(2, .began, Point(x: 10, y: 0), 0.01)])

        var events: [TouchpadIntent] = []
        var t = 0.05
        for i in 1...8 {
            let dy = Double(i) * 15.0
            events += rec.handle([sample(1, .moved, Point(x: 0, y: dy), t), sample(2, .moved, Point(x: 10, y: dy), t)])
            t += 1.0 / 60.0
        }
        events += rec.handle([sample(1, .ended, Point(x: 0, y: 120), t), sample(2, .ended, Point(x: 10, y: 120), t)])

        let velocities = events.compactMap { intent -> Vector2? in
            if case let .scrollPhaseEnded(velocity, _) = intent { return velocity }
            return nil
        }
        #expect(velocities.first.map { $0.length > 0 } == true)
    }

    @Test func axisLockZeroesMinorAxisAfterThresholdDistance() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, Point(x: 0, y: 0), 0)])
        events += rec.handle([sample(2, .began, Point(x: 10, y: 0), 0.01)])

        var t = 0.05
        for i in 1...6 {
            let dy = Double(i) * 10.0
            events += rec.handle([sample(1, .moved, Point(x: 1, y: dy), t), sample(2, .moved, Point(x: 11, y: dy), t)])
            t += 1.0 / 60.0
        }

        let changed = events.compactMap { intent -> Delta? in
            if case let .scrollChanged(d) = intent { return d }
            return nil
        }
        #expect(changed.contains { $0.dx == 0 })
    }

    @Test func pinchEmitsZoomInStep() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, Point(x: 0, y: 0), 0)])
        events += rec.handle([sample(2, .began, Point(x: 10, y: 0), 0.01)])
        // start distance 10. Touches are processed one at a time within a batch, so the pinch-vs-
        // scroll decision (spec §4.2.3: "distance change ≥ 40 pt before scroll commits") is made as
        // soon as the *first*-processed touch's own update alone already crosses the threshold
        // against the other touch's still-stale position — moving touch 1 far enough on its own
        // guarantees that regardless of batch order.
        events += rec.handle([sample(1, .moved, Point(x: -60, y: 0), 0.05), sample(2, .moved, Point(x: 70, y: 0), 0.05)])
        events += rec.handle([sample(1, .moved, Point(x: -110, y: 0), 0.10), sample(2, .moved, Point(x: 120, y: 0), 0.10)])
        #expect(events.contains(.pinch(.zoomIn)))
    }

    @Test func threeFingerSwipeRight() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([
            sample(1, .began, Point(x: 0, y: 0), 0),
            sample(2, .began, Point(x: 10, y: 0), 0.01),
            sample(3, .began, Point(x: 20, y: 0), 0.02),
        ])
        events += rec.handle([
            sample(1, .moved, Point(x: 200, y: 0), 0.1),
            sample(2, .moved, Point(x: 210, y: 0), 0.1),
            sample(3, .moved, Point(x: 220, y: 0), 0.1),
        ])
        #expect(events.contains(.swipe(.right)))
    }

    @Test func threeFingerSwipeLeft() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([
            sample(1, .began, Point(x: 200, y: 0), 0),
            sample(2, .began, Point(x: 210, y: 0), 0.01),
            sample(3, .began, Point(x: 220, y: 0), 0.02),
        ])
        events += rec.handle([
            sample(1, .moved, Point(x: 0, y: 0), 0.1),
            sample(2, .moved, Point(x: 10, y: 0), 0.1),
            sample(3, .moved, Point(x: 20, y: 0), 0.1),
        ])
        #expect(events.contains(.swipe(.left)))
    }

    @Test func threeFingerSwipeDown() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([
            sample(1, .began, Point(x: 0, y: 0), 0),
            sample(2, .began, Point(x: 10, y: 0), 0.01),
            sample(3, .began, Point(x: 20, y: 0), 0.02),
        ])
        events += rec.handle([
            sample(1, .moved, Point(x: 0, y: 200), 0.1),
            sample(2, .moved, Point(x: 10, y: 210), 0.1),
            sample(3, .moved, Point(x: 20, y: 220), 0.1),
        ])
        #expect(events.contains(.swipe(.down)))
    }

    @Test func threeFingerSwipeUp() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([
            sample(1, .began, Point(x: 0, y: 200), 0),
            sample(2, .began, Point(x: 10, y: 210), 0.01),
            sample(3, .began, Point(x: 20, y: 220), 0.02),
        ])
        events += rec.handle([
            sample(1, .moved, Point(x: 0, y: 0), 0.1),
            sample(2, .moved, Point(x: 10, y: 0), 0.1),
            sample(3, .moved, Point(x: 20, y: 0), 0.1),
        ])
        #expect(events.contains(.swipe(.up)))
    }

    @Test func fourFingerTapEmitsFourFingerTap() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([
            sample(1, .began, Point(x: 0, y: 0), 0),
            sample(2, .began, Point(x: 10, y: 0), 0.01),
            sample(3, .began, Point(x: 20, y: 0), 0.02),
            sample(4, .began, Point(x: 30, y: 0), 0.03),
        ])
        events += rec.handle([
            sample(1, .ended, Point(x: 0, y: 0), 0.1),
            sample(2, .ended, Point(x: 10, y: 0), 0.1),
            sample(3, .ended, Point(x: 20, y: 0), 0.1),
            sample(4, .ended, Point(x: 30, y: 0), 0.1),
        ])
        #expect(events.contains(.fourFingerTap))
    }

    // MARK: Palm rejection

    @Test func palmRejectionByRadiusIgnoresTouch() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, .zero, 0, radius: 40)])
        events += rec.handle([sample(1, .moved, Point(x: 50, y: 50), 0.05, radius: 40)])
        events += rec.handle([sample(1, .ended, Point(x: 50, y: 50), 0.1, radius: 40)])
        #expect(events.isEmpty)
    }

    @Test func palmRejectionByEdgeIgnoresTouch() {
        var config = GestureConfig()
        config.screenBounds = Rect(x: 0, y: 0, width: 400, height: 800)
        var rec = GestureRecognizer(config: config)
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, Point(x: 1, y: 400), 0)])
        events += rec.handle([sample(1, .ended, Point(x: 1, y: 400), 0.05)])
        #expect(events.isEmpty)
    }

    @Test func touchNearEdgeButOutsideMarginIsNotRejected() {
        var config = GestureConfig()
        config.screenBounds = Rect(x: 0, y: 0, width: 400, height: 800)
        var rec = GestureRecognizer(config: config)
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(1, .began, Point(x: 10, y: 400), 0)])
        events += rec.handle([sample(1, .ended, Point(x: 10, y: 400), 0.05)])
        #expect(events.contains(.click(button: .left, kind: .tap, count: 1)))
    }

    @Test func tooManyConcurrentTouchesRejectsWholeSet() {
        var rec = GestureRecognizer()
        var events: [TouchpadIntent] = []
        events += rec.handle([
            sample(1, .began, Point(x: 0, y: 0), 0),
            sample(2, .began, Point(x: 10, y: 0), 0.01),
            sample(3, .began, Point(x: 20, y: 0), 0.02),
            sample(4, .began, Point(x: 30, y: 0), 0.03),
            sample(5, .began, Point(x: 40, y: 0), 0.04),
        ])
        events += rec.handle([
            sample(1, .ended, Point(x: 0, y: 0), 0.1),
            sample(2, .ended, Point(x: 10, y: 0), 0.1),
            sample(3, .ended, Point(x: 20, y: 0), 0.1),
            sample(4, .ended, Point(x: 30, y: 0), 0.1),
            sample(5, .ended, Point(x: 40, y: 0), 0.1),
        ])
        #expect(events.isEmpty)
    }

    @Test func recognizerRecoversToIdleAfterRejectedGestureFullyLifts() {
        var rec = GestureRecognizer()
        _ = rec.handle([
            sample(1, .began, Point(x: 0, y: 0), 0),
            sample(2, .began, Point(x: 10, y: 0), 0.01),
            sample(3, .began, Point(x: 20, y: 0), 0.02),
            sample(4, .began, Point(x: 30, y: 0), 0.03),
            sample(5, .began, Point(x: 40, y: 0), 0.04),
        ])
        _ = rec.handle([
            sample(1, .ended, Point(x: 0, y: 0), 0.1),
            sample(2, .ended, Point(x: 10, y: 0), 0.1),
            sample(3, .ended, Point(x: 20, y: 0), 0.1),
            sample(4, .ended, Point(x: 30, y: 0), 0.1),
            sample(5, .ended, Point(x: 40, y: 0), 0.1),
        ])

        // A fresh, ordinary tap afterward should work normally again.
        var events: [TouchpadIntent] = []
        events += rec.handle([sample(6, .began, Point(x: 0, y: 0), 1.0)])
        events += rec.handle([sample(6, .ended, Point(x: 0, y: 0), 1.05)])
        #expect(events.contains(.click(button: .left, kind: .tap, count: 1)))
    }
}
