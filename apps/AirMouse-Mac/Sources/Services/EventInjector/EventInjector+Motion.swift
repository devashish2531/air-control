// EventInjector+Motion — spec §5.3.2 (pointer move), §5.3.8 (multi-display/clamp/recenter), §5.4
// (acceleration curve). Also §5.3.3 (clicks) and §3.6/§5.3.4 (scroll), which share this file's pointer
// state (`virtualPos`, `heldButtons`) closely enough to belong alongside motion rather than split
// further.
import AirMouseFilters
import AirMouseProtocol
import AppKit
import CoreGraphics

extension EventInjector {
    // MARK: - Motion (spec §5.3.2)

    /// One motion datagram's already-decoded (points, not wire eighth-point fixed values — that
    /// conversion is `MotionPayload`'s / the caller's job) pointer delta. `sampleInterval` is the
    /// client-timestamp gap to the previous datagram of the same source, spec-clamped 4…50 ms by
    /// `AccelerationCurve.apply` itself.
    public func applyMotion(
        dx: Double,
        dy: Double,
        source motionSource: MotionSource,
        flags: MotionFlags,
        sampleInterval: TimeInterval
    ) {
        guard !paused else {
            counters.droppedWhilePaused += 1
            return
        }
        noteActivity()

        let now = clock.now()
        let isFirstOfBurst = isBurstStart(now: now)
        if isFirstOfBurst {
            // spec §5.3.2: "At the start of a burst ... re-sync virtualPos = CGEvent(source: nil)!
            // .location" — a local mouse move since the last burst must not leave us stale.
            virtualPos = pointerLocationProvider()
        }

        if flags.contains(.motionEnd) {
            // spec §3.5.6: "motionEnd flag ... host zeroes velocity and remainder."
            remainder = .zero
            lastMotionAt = now
            return
        }

        let delta = Delta(dx: dx, dy: dy)
        let accelerated = accelerationCurve.apply(
            delta,
            sampleInterval: sampleInterval,
            isFirstOfBurst: isFirstOfBurst,
            isGyroSource: motionSource == .gyro
        )

        let fx = accelerated.dx + remainder.x
        let fy = accelerated.dy + remainder.y
        let ix = fx.rounded(.towardZero)
        let iy = fy.rounded(.towardZero)
        remainder = Vector2(x: fx - ix, y: fy - iy)
        lastMotionAt = now

        // spec §5.3.2: "If ix == iy == 0 no event is posted."
        guard ix != 0 || iy != 0 else { return }

        let proposed = Point(x: virtualPos.x + ix, y: virtualPos.y + iy)
        let current = Point(x: virtualPos.x, y: virtualPos.y)
        let clamped = displayClamp.clamp(target: proposed, current: current)
        let target = CGPoint(x: clamped.x, y: clamped.y)

        let primary = primaryHeldButton()
        let type: CGEventType = primary.map(dragEventType) ?? .mouseMoved
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: target,
            mouseButton: cgButton(primary ?? .left)
        ) else { return }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(ix))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(iy))
        event.flags = currentCGEventFlags()

        guard postSigned(event, category: .motion) else { return }
        counters.motionEventsPosted += 1
        virtualPos = target
    }

    /// spec §5.3.8: "`recenter` → `virtualPos = center(display containing virtualPos)`, post
    /// `mouseMoved` with deltas = the jump, reset remainder."
    public func recenter() {
        guard !paused else { return }
        let current = Point(x: virtualPos.x, y: virtualPos.y)
        guard let center = displayClamp.recenterPosition(current: current) else { return }
        let ix = center.x - current.x
        let iy = center.y - current.y
        let target = CGPoint(x: center.x, y: center.y)
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: target,
            mouseButton: .left
        ) else { return }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(ix.rounded()))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(iy.rounded()))
        event.flags = currentCGEventFlags()
        guard postSigned(event, category: .motion) else { return }
        virtualPos = target
        remainder = .zero
    }

    func isBurstStart(now: TimeInterval) -> Bool {
        guard let last = lastMotionAt else { return true }
        // spec §3.5.6: "Host motion pause: if no motion datagram arrives for 100 ms while a stream
        // was active, the host treats the stream as paused" — spec §5.3.2 burst-start re-sync uses
        // the same 100 ms figure.
        return (now - last) >= 0.100
    }

    func primaryHeldButton() -> MouseButton? {
        if heldButtons.contains(.left) { return .left }
        if heldButtons.contains(.right) { return .right }
        if heldButtons.contains(.middle) { return .middle }
        return nil
    }

    func cgButton(_ button: MouseButton) -> CGMouseButton {
        switch button {
        case .left: .left
        case .right: .right
        case .middle: .center
        }
    }

    func dragEventType(for button: MouseButton) -> CGEventType {
        switch button {
        case .left: .leftMouseDragged
        case .right: .rightMouseDragged
        case .middle: .otherMouseDragged
        }
    }

    // MARK: - Clicks (spec §5.3.3)

    /// `down`/`up` posting. `clickCount` is the wire's requested `mouseEventClickState`; sanitized
    /// per spec against the previous click of the same button (see `sanitizedClickCount`).
    public func click(button: MouseButton, isDown: Bool, clickCount: Int) {
        guard !paused else {
            counters.droppedWhilePaused += 1
            return
        }
        noteActivity()

        let position = virtualPos
        let count = sanitizedClickCount(button: button, requested: clickCount, at: position)
        guard let event = mouseClickEvent(button: button, isDown: isDown, position: position, clickState: count) else { return }
        guard postSigned(event, category: .click) else { return }
        counters.clicksPosted += 1

        if isDown {
            heldButtons.insert(button)
        } else {
            heldButtons.remove(button)
        }
    }

    /// spec §5.3.3: "`click{tap}` → down, then up scheduled on a `DispatchSourceTimer` after 15 ms
    /// (never `usleep`)."
    public func clickTap(button: MouseButton, clickCount: Int = 1) {
        click(button: button, isDown: true, clickCount: clickCount)
        scheduleAfter(Self.clickTapGap) { isolated in
            isolated.click(button: button, isDown: false, clickCount: clickCount)
        }
    }

    func mouseClickEvent(button: MouseButton, isDown: Bool, position: CGPoint, clickState: Int) -> CGEvent? {
        let type: CGEventType
        switch (button, isDown) {
        case (.left, true): type = .leftMouseDown
        case (.left, false): type = .leftMouseUp
        case (.right, true): type = .rightMouseDown
        case (.right, false): type = .rightMouseUp
        case (.middle, true): type = .otherMouseDown
        case (.middle, false): type = .otherMouseUp
        }
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: position,
            mouseButton: cgButton(button)
        ) else { return nil }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        if button == .middle {
            // research A1 / spec §5.3.3: "Middle = `.otherMouseDown/Up` with `mouseButton: .center`,
            // button number 2."
            event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        }
        event.flags = currentCGEventFlags()
        return event
    }

    /// spec §5.3.3: "Sanity: `count` clamped to 1 if the previous click of that button was
    /// > 1.5 × `doubleClickIntervalMs` ago or at a position > 16 pt away."
    func sanitizedClickCount(button: MouseButton, requested: Int, at position: CGPoint) -> Int {
        defer {
            lastClickByButton[button] = LastClick(at: clock.now(), position: position, count: max(1, requested))
        }
        guard requested > 1, let last = lastClickByButton[button] else { return max(1, requested) }
        let elapsed = clock.now() - last.at
        let maxInterval = NSEvent.doubleClickInterval * Self.clickCountIntervalMultiplier
        let distance = hypot(position.x - last.position.x, position.y - last.position.y)
        if elapsed > maxInterval || distance > Self.clickCountMaxPositionDelta {
            return 1
        }
        return requested
    }

    // MARK: - Scroll (spec §3.6, §5.3.4)

    /// Discrete/continuous signal for one `scroll(...)` call. `.began`/`.ended`/`.cancel` mirror the
    /// wire's `ScrollPhaseKind` (control-channel `scrollPhase` message, spec §3.4.5); `.changed` is a
    /// per-datagram delta from the motion channel (implicit — the wire has no discrete "changed"
    /// message, spec §3.6.2's table).
    public enum ScrollPhaseSignal: Sendable, Equatable {
        case began
        case changed
        case ended
        case cancel
    }

    /// `dx`/`dy` are already-decoded finger-travel points (see `applyMotion`'s doc comment on units).
    /// `isMomentum` mirrors the wire's `scrollPhase{ended}.momentum` field (spec §3.4.5: "`false`
    /// suppresses momentum") and only matters on `.ended`; `liftVelocity` is that message's `vx`/`vy`
    /// (finger-travel pt/s at lift).
    public func scroll(
        phase: ScrollPhaseSignal,
        dx: Double = 0,
        dy: Double = 0,
        isMomentum: Bool = true,
        liftVelocity: Vector2 = .zero
    ) async {
        guard !paused else {
            counters.droppedWhilePaused += 1
            return
        }
        noteActivity()

        switch phase {
        case .began:
            scrollSessionOpen = true
            scrollRemainder = .zero
            await momentumEngine.cancel()
            postScrollEvent(pixelDelta: .zero, cgScrollPhase: .began, momentumPhase: nil)

        case .changed:
            scrollSessionOpen = true
            let pixels = scrollGain.pixels(fromPointDelta: Delta(dx: dx, dy: dy))
            let fx = pixels.dx + scrollRemainder.x
            let fy = pixels.dy + scrollRemainder.y
            let ix = fx.rounded(.towardZero)
            let iy = fy.rounded(.towardZero)
            scrollRemainder = Vector2(x: fx - ix, y: fy - iy)
            guard ix != 0 || iy != 0 else { return }
            // spec §3.6.3: momentum is "cancelled by ... any new scroll delta".
            await momentumEngine.cancel()
            postScrollEvent(pixelDelta: Vector2(x: ix, y: iy), cgScrollPhase: .changed, momentumPhase: nil)

        case .ended:
            postScrollEvent(pixelDelta: .zero, cgScrollPhase: .ended, momentumPhase: nil)
            scrollSessionOpen = false
            scrollRemainder = .zero
            guard isMomentum, liftVelocity.length >= MomentumSynthesizer.minFlingVelocity else { return }
            let gain = scrollGain.gain * (scrollGain.invertForNatural ? -1 : 1)
            await momentumEngine.start(velocity: liftVelocity, gain: gain)

        case .cancel:
            scrollSessionOpen = false
            scrollRemainder = .zero
            await momentumEngine.cancel()
        }
    }

    /// Raw `CGScrollPhase` values (`CGEventTypes.h`); see `MomentumEngine`'s matching comment for why
    /// these are posted as raw integers rather than via the imported `CGScrollPhase` enum cases.
    private enum RawScrollPhase: Int64 {
        case began = 1
        case changed = 2
        case ended = 4
        case cancelled = 8
    }

    private func postScrollEvent(pixelDelta: Vector2, cgScrollPhase: RawScrollPhase, momentumPhase: Int64?) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(pixelDelta.y),
            wheel2: Int32(pixelDelta.x),
            wheel3: 0
        ) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: cgScrollPhase.rawValue)
        if let momentumPhase {
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        }
        event.flags = currentCGEventFlags()
        guard postSigned(event, category: .scroll) else { return }
        counters.scrollEventsPosted += 1
    }
}
