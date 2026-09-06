import Foundation

/// Touchpad tap/drag/scroll/swipe disambiguation state machine (spec §4.2.3's Mermaid diagram,
/// §4.2.5's multi-finger wire mapping, §4.2.6's palm rejection). Pure and synchronous: feed it
/// `TouchSample`s (as a `UIKit` view would from `touchesBegan/Moved/Ended/Cancelled`) via
/// `handle(_:)`, and call `advanceTime(to:)` periodically so purely time-driven transitions
/// (long-press timeout, tap-and-drag window closing, drag-lock timeout) fire even with no new touch.
public struct GestureRecognizer: Sendable {
    public var config: GestureConfig

    // MARK: State

    private enum Phase: Equatable {
        case idle
        case touch1
        case moving
        case longPress
        case tapDone
        case dragArmed
        case dragging
        case dragLocked
        case touchN
        case scrolling
        case pinching
        case threeFinger
    }

    private enum Axis: Equatable { case x, y }
    private enum AxisLockState: Equatable { case undecided, locked(Axis), free }

    private struct ActiveTouch {
        var startPosition: Point
        var position: Point
        var startTime: TimeInterval
        var maxMovement: Double = 0
        var rejected: Bool = false
    }

    private var phase: Phase = .idle
    private var touches: [TouchID: ActiveTouch] = [:]
    private var primaryID: TouchID?
    private var gestureIDs: Set<TouchID> = []
    private var gestureStartTime: TimeInterval = 0
    private var maxConcurrentThisGesture: Int = 0
    private var allRejectedThisGesture = false
    private var suppressMoveUntil: TimeInterval = -.infinity

    private var tapCount = 0
    private var lastTapUpTime: TimeInterval = -.infinity
    private var lastTapUpPosition: Point = .zero

    private var dragLockDeadline: TimeInterval = .infinity

    private var axisLockState: AxisLockState = .undecided
    private var scrollStartCentroid: Point = .zero
    private var scrollLastCentroid: Point = .zero
    private var recentVelocities: [Vector2] = []
    private var lastScrollFrameTime: TimeInterval?

    private var pinchBaseDistance: Double = 0
    private var pinchAccum: Double = 0

    private var threeFingerAnchor: Point = .zero
    private var threeFingerSwiped = false

    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
    }

    public mutating func reset() {
        abandonGesture()
        touches = [:]
        allRejectedThisGesture = false
        tapCount = 0
        lastTapUpTime = -.infinity
        lastTapUpPosition = .zero
        dragLockDeadline = .infinity
        suppressMoveUntil = -.infinity
    }

    // MARK: Public entry points

    /// Processes a batch of touch updates (as UIKit would deliver in one `touchesBegan/Moved/…`
    /// callback), in order, running `advanceTime(to:)` ahead of each so time-based transitions using
    /// that sample's own timestamp resolve first.
    public mutating func handle(_ samples: [TouchSample]) -> [TouchpadIntent] {
        var out: [TouchpadIntent] = []
        for sample in samples {
            out.append(contentsOf: advanceTime(to: sample.timestamp))
            out.append(contentsOf: handleOne(sample))
        }
        return out
    }

    /// Resolves purely time-driven transitions with no new touch: long-press timeout, the
    /// tap-and-drag window closing, and the drag-lock timeout. Safe to call with a timestamp at or
    /// before the last-seen time (a no-op in that case for the checks that need forward progress).
    @discardableResult
    public mutating func advanceTime(to timestamp: TimeInterval) -> [TouchpadIntent] {
        var out: [TouchpadIntent] = []
        switch phase {
        case .touch1:
            if config.longPressRightClickEnabled, let id = primaryID, let t = touches[id],
               timestamp - t.startTime >= config.longPressDuration, t.maxMovement <= config.tapMaxMovement {
                phase = .longPress
                out.append(.click(button: .right, kind: .tap, count: 1))
                out.append(.longPressHaptic)
            }
        case .tapDone:
            if timestamp - lastTapUpTime >= config.tapAndDragWindow {
                phase = .idle
            }
        case .dragLocked:
            if primaryID == nil, timestamp >= dragLockDeadline {
                phase = .idle
                dragLockDeadline = .infinity
                out.append(.click(button: .left, kind: .up, count: 1))
                out.append(.dragLockDisengaged)
                out.append(.motionEnd)
            }
        default:
            break
        }
        return out
    }

    // MARK: One touch sample

    private mutating func handleOne(_ sample: TouchSample) -> [TouchpadIntent] {
        switch sample.phase {
        case .began: return handleBegan(sample)
        case .moved, .stationary: return handleMoved(sample)
        case .ended, .cancelled: return handleEnded(sample)
        }
    }

    private mutating func handleBegan(_ sample: TouchSample) -> [TouchpadIntent] {
        let rejected = shouldReject(sample)
        touches[sample.id] = ActiveTouch(
            startPosition: sample.position, position: sample.position,
            startTime: sample.timestamp, maxMovement: 0, rejected: rejected
        )

        if allRejectedThisGesture { return [] }

        if touches.count > config.maxConcurrentTouches {
            allRejectedThisGesture = true
            abandonGesture()
            return []
        }
        if rejected { return [] }

        var out: [TouchpadIntent] = []
        switch phase {
        case .idle:
            primaryID = sample.id
            gestureIDs = [sample.id]
            gestureStartTime = sample.timestamp
            maxConcurrentThisGesture = 1
            phase = .touch1
        case .touch1, .moving:
            gestureIDs.insert(sample.id)
            maxConcurrentThisGesture = max(maxConcurrentThisGesture, gestureIDs.count)
            primaryID = nil
            phase = .touchN
        case .tapDone:
            out.append(contentsOf: handleBeganDuringTapDone(sample))
        case .dragArmed, .dragging:
            break // spec doesn't define multi-finger composition mid single-finger drag; ignore extra
        case .dragLocked:
            if primaryID == nil {
                primaryID = sample.id
                gestureIDs = [sample.id]
                dragLockDeadline = .infinity // a touch is present; pause the no-touch timeout
            }
        case .longPress:
            break
        case .touchN:
            gestureIDs.insert(sample.id)
            maxConcurrentThisGesture = max(maxConcurrentThisGesture, gestureIDs.count)
        case .scrolling, .pinching, .threeFinger:
            break // committed gesture shape; ignore fingers joining after the fact
        }
        return out
    }

    private mutating func handleBeganDuringTapDone(_ sample: TouchSample) -> [TouchpadIntent] {
        let elapsed = sample.timestamp - lastTapUpTime
        primaryID = sample.id
        gestureIDs = [sample.id]
        gestureStartTime = sample.timestamp
        maxConcurrentThisGesture = 1
        if config.tapAndDragEnabled && elapsed <= config.tapAndDragWindow {
            phase = .dragArmed
        } else {
            phase = .touch1
        }
        return []
    }

    private mutating func handleMoved(_ sample: TouchSample) -> [TouchpadIntent] {
        guard var t = touches[sample.id] else { return [] }
        let previous = t.position
        t.position = sample.position
        t.maxMovement = max(t.maxMovement, (sample.position - t.startPosition).length)
        touches[sample.id] = t

        guard !t.rejected, !allRejectedThisGesture else { return [] }

        var out: [TouchpadIntent] = []
        switch phase {
        case .touch1:
            if t.maxMovement > config.tapMaxMovement { phase = .moving }
            if canEmitPrimaryMove(t, at: sample.timestamp) {
                out.append(.move(Delta(sample.position - previous)))
            }
        case .moving:
            if canEmitPrimaryMove(t, at: sample.timestamp) {
                out.append(.move(Delta(sample.position - previous)))
            }
        case .dragArmed:
            if t.maxMovement > config.tapMaxMovement {
                phase = .dragging
                out.append(.click(button: .left, kind: .down, count: 1))
                out.append(.move(Delta(sample.position - previous)))
            }
        case .dragging:
            out.append(.move(Delta(sample.position - previous)))
        case .dragLocked:
            if sample.id == primaryID, t.maxMovement > 0 {
                phase = .dragging
                dragLockDeadline = .infinity
                out.append(.move(Delta(sample.position - previous)))
            }
        case .longPress:
            break
        case .touchN:
            out.append(contentsOf: resolveTouchN())
        case .scrolling:
            out.append(contentsOf: emitScroll(at: sample.timestamp))
        case .pinching:
            out.append(contentsOf: emitPinch())
        case .threeFinger:
            out.append(contentsOf: emitThreeFinger())
        case .idle, .tapDone:
            break
        }
        return out
    }

    private mutating func handleEnded(_ sample: TouchSample) -> [TouchpadIntent] {
        guard let t = touches.removeValue(forKey: sample.id) else { return [] }

        if allRejectedThisGesture {
            if touches.isEmpty { allRejectedThisGesture = false; phase = .idle }
            return []
        }
        if t.rejected { return [] }

        var out: [TouchpadIntent] = []
        switch phase {
        case .touch1:
            out.append(contentsOf: resolveSingleFingerLift(sample, t))
        case .moving:
            phase = .idle
            primaryID = nil
            out.append(.motionEnd)
        case .longPress:
            phase = .idle
            primaryID = nil
        case .dragArmed:
            out.append(contentsOf: resolveSingleFingerLift(sample, t))
        case .dragging:
            if let timeout = config.dragLockTimeout {
                phase = .dragLocked
                primaryID = nil
                dragLockDeadline = sample.timestamp + timeout
                out.append(.dragLockEngaged)
            } else {
                phase = .idle
                primaryID = nil
                out.append(.click(button: .left, kind: .up, count: 1))
                out.append(.motionEnd)
            }
        case .dragLocked:
            if sample.id == primaryID {
                phase = .idle
                primaryID = nil
                dragLockDeadline = .infinity
                out.append(.click(button: .left, kind: .up, count: 1))
                out.append(.dragLockDisengaged)
                out.append(.motionEnd)
            }
        case .touchN, .scrolling, .pinching, .threeFinger:
            out.append(contentsOf: handleMultiFingerLift(sample))
        case .idle, .tapDone:
            break
        }
        return out
    }

    private mutating func resolveSingleFingerLift(_ sample: TouchSample, _ t: ActiveTouch) -> [TouchpadIntent] {
        let elapsed = sample.timestamp - t.startTime
        if sample.phase == .cancelled {
            phase = .idle
            primaryID = nil
            return [.motionEnd]
        }
        guard elapsed <= config.tapMaxDuration, t.maxMovement <= config.tapMaxMovement else {
            phase = .idle
            primaryID = nil
            return [.motionEnd]
        }
        let count = nextTapCount(at: sample.timestamp, position: sample.position)
        lastTapUpTime = sample.timestamp
        lastTapUpPosition = sample.position
        suppressMoveUntil = sample.timestamp + config.motionSuppressAfterTap
        phase = .tapDone
        primaryID = nil
        return [.click(button: .left, kind: .tap, count: count)]
    }

    private mutating func handleMultiFingerLift(_ sample: TouchSample) -> [TouchpadIntent] {
        gestureIDs.remove(sample.id)
        guard gestureIDs.isEmpty else { return [] }

        var out: [TouchpadIntent] = []
        switch phase {
        case .scrolling:
            out.append(.scrollPhaseEnded(velocity: meanRecentVelocity(), momentum: config.momentumEnabled))
        case .touchN:
            let elapsed = sample.timestamp - gestureStartTime
            if elapsed <= config.tapMaxDuration {
                if maxConcurrentThisGesture == 2 {
                    out.append(.click(button: .right, kind: .tap, count: 1))
                } else if maxConcurrentThisGesture == 4 {
                    out.append(.fourFingerTap)
                }
            }
        default:
            break
        }
        phase = .idle
        primaryID = nil
        out.append(.motionEnd)
        return out
    }

    // MARK: Multi-finger resolution

    private mutating func resolveTouchN() -> [TouchpadIntent] {
        let ids = gestureIDs
        let count = ids.count
        let anyMoved = ids.contains { touches[$0]?.maxMovement ?? 0 > config.tapMaxMovement }
        guard anyMoved else { return [] }

        if count == 2 {
            let pair = Array(ids)
            guard pair.count == 2, let a = touches[pair[0]], let b = touches[pair[1]] else { return [] }
            let startDistance = (a.startPosition - b.startPosition).length
            let currentDistance = (a.position - b.position).length
            if abs(currentDistance - startDistance) >= config.pinchThreshold {
                phase = .pinching
                pinchBaseDistance = currentDistance
                pinchAccum = 0
                return []
            }
            phase = .scrolling
            axisLockState = .undecided
            let c = centroid(of: ids)
            scrollStartCentroid = c
            scrollLastCentroid = c
            recentVelocities = []
            lastScrollFrameTime = nil
            return [.scrollPhaseBegan]
        } else if count == 3 {
            phase = .threeFinger
            threeFingerAnchor = centroid(of: ids)
            threeFingerSwiped = false
        }
        // 4+ fingers moving together has no defined continuous gesture (spec only defines a quick
        // four-finger tap); leave phase as .touchN so a subsequent all-up can still resolve to it.
        return []
    }

    private mutating func emitScroll(at timestamp: TimeInterval) -> [TouchpadIntent] {
        let c = centroid(of: gestureIDs)
        var delta = c - scrollLastCentroid
        scrollLastCentroid = c
        guard delta != .zero else { return [] }

        if config.scrollAxisLockEnabled {
            delta = applyAxisLock(delta)
        }

        if let lastT = lastScrollFrameTime {
            let dt = Swift.max(timestamp - lastT, 0.001)
            let velocity = delta * (1.0 / dt)
            recentVelocities.append(velocity)
            if recentVelocities.count > 3 { recentVelocities.removeFirst() }
        }
        lastScrollFrameTime = timestamp

        return [.scrollChanged(Delta(delta))]
    }

    private mutating func applyAxisLock(_ rawDelta: Vector2) -> Vector2 {
        switch axisLockState {
        case .locked(.x): return Vector2(x: rawDelta.x, y: 0)
        case .locked(.y): return Vector2(x: 0, y: rawDelta.y)
        case .free: return rawDelta
        case .undecided:
            let total = centroid(of: gestureIDs) - scrollStartCentroid
            guard total.length >= config.scrollAxisLockDistance else { return rawDelta }
            let angleFromHorizontal = atan2(abs(total.y), abs(total.x)) * 180 / Double.pi
            if angleFromHorizontal <= config.scrollAxisLockAngleDegrees {
                axisLockState = .locked(.x)
                return Vector2(x: rawDelta.x, y: 0)
            } else if angleFromHorizontal >= (90 - config.scrollAxisLockAngleDegrees) {
                axisLockState = .locked(.y)
                return Vector2(x: 0, y: rawDelta.y)
            } else {
                axisLockState = .free
                return rawDelta
            }
        }
    }

    private mutating func emitPinch() -> [TouchpadIntent] {
        let pair = Array(gestureIDs)
        guard pair.count == 2, let a = touches[pair[0]], let b = touches[pair[1]] else { return [] }
        let currentDistance = (a.position - b.position).length
        pinchAccum += currentDistance - pinchBaseDistance
        pinchBaseDistance = currentDistance

        var out: [TouchpadIntent] = []
        while abs(pinchAccum) >= config.pinchThreshold {
            if pinchAccum > 0 {
                out.append(.pinch(.zoomIn))
                pinchAccum -= config.pinchThreshold
            } else {
                out.append(.pinch(.zoomOut))
                pinchAccum += config.pinchThreshold
            }
        }
        return out
    }

    private mutating func emitThreeFinger() -> [TouchpadIntent] {
        guard !threeFingerSwiped else { return [] }
        let c = centroid(of: gestureIDs)
        let displacement = c - threeFingerAnchor
        guard displacement.length >= config.threeFingerSwipeDistance else { return [] }
        threeFingerSwiped = true
        let direction: SwipeDirection
        if abs(displacement.x) >= abs(displacement.y) {
            direction = displacement.x >= 0 ? .right : .left
        } else {
            direction = displacement.y >= 0 ? .down : .up
        }
        return [.swipe(direction)]
    }

    // MARK: Helpers

    private func shouldReject(_ sample: TouchSample) -> Bool {
        if sample.majorRadius > config.palmMajorRadius { return true }
        if let bounds = config.screenBounds, bounds.distanceToNearestEdge(sample.position) < config.edgeMargin {
            return true
        }
        return false
    }

    private func canEmitPrimaryMove(_ t: ActiveTouch, at timestamp: TimeInterval) -> Bool {
        if timestamp < suppressMoveUntil { return false }
        if timestamp - gestureStartTime < config.fingerCountSettle && t.maxMovement <= config.tapMaxMovement {
            return false
        }
        return true
    }

    private mutating func nextTapCount(at timestamp: TimeInterval, position: Point) -> Int {
        if tapCount > 0,
           timestamp - lastTapUpTime <= config.doubleTapInterval,
           (position - lastTapUpPosition).length <= config.doubleTapMaxMovement {
            tapCount = min(tapCount + 1, config.maxTapCount)
        } else {
            tapCount = 1
        }
        return tapCount
    }

    private func centroid(of ids: Set<TouchID>) -> Point {
        guard !ids.isEmpty else { return .zero }
        var sum = Vector2.zero
        for id in ids {
            if let t = touches[id] { sum = sum + t.position }
        }
        return sum * (1.0 / Double(ids.count))
    }

    private func meanRecentVelocity() -> Vector2 {
        guard !recentVelocities.isEmpty else { return .zero }
        let sum = recentVelocities.reduce(Vector2.zero, +)
        return sum * (1.0 / Double(recentVelocities.count))
    }

    private mutating func abandonGesture() {
        phase = .idle
        primaryID = nil
        gestureIDs = []
        axisLockState = .undecided
        recentVelocities = []
        lastScrollFrameTime = nil
        pinchBaseDistance = 0
        pinchAccum = 0
        threeFingerSwiped = false
    }
}
