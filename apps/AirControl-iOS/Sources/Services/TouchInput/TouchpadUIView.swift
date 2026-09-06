// Services/TouchInput/TouchpadUIView.swift
// `TouchpadView: UIView` (spec §4.2.1): `isMultipleTouchEnabled = true`; overrides
// `touchesBegan/Moved/Ended/Cancelled`; iterates `event.coalescedTouches(for:)` (and
// `predictedTouches(for:)` only when Prediction is on); feeds `AirControlFilters.GestureRecognizer`
// and forwards its `TouchpadIntent`s to a `TouchpadIntentSink`.
//
// Runs entirely on the main thread (touch delivery, spec §4.2.1) with zero allocation in the
// per-touch hot loop beyond what UIKit itself allocates for `coalescedTouches`/`predictedTouches`
// (arrays UIKit already owns) — this type does not allocate its own buffers per callback.
//
// A `CADisplayLink` (added only while the view is in a window) drives
// `GestureRecognizer.advanceTime(to:)` every frame so purely time-driven transitions (long-press
// timeout, tap-and-drag window closing, drag-lock timeout — spec §4.2.3) fire even while a finger
// is held still and UIKit isn't delivering `touchesMoved` for it. This is a UI-thread convenience
// timer, not the motion hot path the "never a batching timer" rule (spec §3.5.7) governs — that
// rule is about the send queue, not gesture-state polling.
//
// TODO(spec §4.1.10 FR-IP-003): `GCMouse.current` / `UIPointerInteraction` iPad trackpad
// passthrough (`source = 2` motion datagrams, system pointer hidden with `.hidden` style) is not
// implemented here — out of scope for this pass; `.indirect`/`.indirectPointer` touches are
// dropped (see `TouchSampleConversion`) rather than misrouted into the finger state machine.

import UIKit
import QuartzCore
import Foundation
import os
import AirControlFilters

#if DEBUG
/// DEBUG-only, process-wide touch-delivery counters (read by `TouchpadDebugMotionLabel`,
/// Features/Touchpad) — proves whether `touchesBegan`/`touchesMoved` are ever invoked on this
/// UIKit view at all, independent of everything downstream (`GestureRecognizer`,
/// `TouchpadIntentSink`, `MotionPublisher`). `nonisolated`/lock-backed like
/// `MotionPublisher.stats` so it can be read from the SwiftUI (`@MainActor`) debug label without
/// caring about `TouchpadUIView`'s own isolation.
enum TouchpadUIViewDebugCounters {
    private static let box = OSAllocatedUnfairLock(initialState: (began: 0, moved: 0))
    static func recordBegan() { box.withLock { $0.began += 1 } }
    static func recordMoved() { box.withLock { $0.moved += 1 } }
    static var snapshot: (began: Int, moved: Int) { box.withLock { $0 } }
}
#endif

@MainActor
public final class TouchpadUIView: UIView {
    /// Where recognized intents go. `weak` because the owning `TouchpadController` (an
    /// `@Observable` view-model-ish object) outlives this view's lifecycle only loosely — the
    /// `UIViewRepresentable` coordinator is the strong owner of both.
    public weak var intentSink: (any TouchpadIntentSink)?

    /// Prediction Labs flag (spec §3.5.6 default off; §4.2.1). Only the primary single-finger
    /// cursor-move touch is extrapolated (spec: "single-finger move" is the moving primary touch).
    public var predictionEnabled: Bool = false

    public var config: GestureConfig {
        get { recognizer.config }
        set { recognizer.config = newValue }
    }

    private var recognizer = GestureRecognizer()
    private var identity = TouchIdentityMap()
    private var displayLink: CADisplayLink?
    /// Accumulated, not-yet-applied predicted contribution (spec §3.5.6: "the next real frame
    /// subtracts the predicted contribution so the integral stays exact"). Single scalar because
    /// only one touch (the primary cursor-move touch) is ever predicted at a time.
    private var pendingPredictedDelta: Delta = .zero

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityLabel = String(
            localized: "Touchpad surface",
            comment: "Accessibility label for the touchpad surface (spec §4.8)"
        )
        accessibilityHint = String(
            localized: "Move one finger to move the pointer. Tap to click. Two fingers to scroll.",
            comment: "Accessibility hint for the touchpad surface"
        )
    }

    // `CADisplayLink` is invalidated in `didMoveToWindow()` when the view leaves its window (the
    // normal UIKit removal path). No `deinit` cleanup here: `CADisplayLink` isn't `Sendable`, and
    // a `@MainActor` type's `deinit` runs in a nonisolated context in Swift 6, so it cannot touch
    // a main-actor-isolated non-Sendable stored property directly.

    // MARK: Lifecycle

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startTicking()
        } else {
            stopTicking()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        recognizer.config.screenBounds = Rect(x: 0, y: 0, width: bounds.width, height: bounds.height)
    }

    private func startTicking() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopTicking() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let intents = recognizer.advanceTime(to: now)
        guard !intents.isEmpty else { return }
        intentSink?.handle(intents, timestamp: now, predicted: false)
    }

    // MARK: Touch delivery (spec §4.2.1)

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        #if DEBUG
        TouchpadUIViewDebugCounters.recordBegan()
        #endif
        emit(samples(for: touches, event: event, overridingPhase: .began))
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        #if DEBUG
        TouchpadUIViewDebugCounters.recordMoved()
        #endif
        emit(samples(for: touches, event: event, overridingPhase: .moved))
        if predictionEnabled {
            emitPrediction(for: touches, event: event)
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        emit(samples(for: touches, event: event, overridingPhase: .ended))
        for touch in touches { identity.release(ObjectIdentifier(touch)) }
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        emit(samples(for: touches, event: event, overridingPhase: .cancelled))
        for touch in touches { identity.release(ObjectIdentifier(touch)) }
    }

    // MARK: Conversion

    private func samples(for touches: Set<UITouch>, event: UIEvent?, overridingPhase: TouchPhase) -> [TouchSample] {
        var out: [TouchSample] = []
        out.reserveCapacity(touches.count)
        for touch in touches {
            let id = identity.id(for: ObjectIdentifier(touch))
            for coalesced in event?.coalescedTouches(for: touch) ?? [touch] {
                guard let raw = rawSample(id: id, touch: coalesced, phase: overridingPhase) else { continue }
                if let sample = TouchSampleConversion.touchSample(from: raw) {
                    out.append(sample)
                }
            }
        }
        return out
    }

    private func rawSample(id: Int, touch: UITouch, phase: TouchPhase) -> RawTouchSample? {
        let location = touch.preciseLocation(in: self)
        return RawTouchSample(
            touchID: id,
            phase: phase,
            x: Double(location.x),
            y: Double(location.y),
            timestamp: touch.timestamp,
            majorRadius: Double(touch.majorRadius),
            type: rawType(for: touch.type)
        )
    }

    private func rawType(for type: UITouch.TouchType) -> RawTouchType {
        switch type {
        case .direct: return .direct
        case .pencil: return .pencil
        case .indirect: return .indirect
        case .indirectPointer: return .indirectPointer
        @unknown default: return .indirect
        }
    }

    /// Processes each `TouchSample` one at a time (rather than handing the whole batch to
    /// `GestureRecognizer.handle(_:)` at once) so every emitted intent batch can be tagged with
    /// the timestamp of the specific sample that produced it — coalesced touches (spec §4.2.1)
    /// each carry their own `timestamp`, and the wire payload needs the true per-sample clock
    /// reading, not one timestamp for the whole `touchesMoved` callback.
    private func emit(_ samples: [TouchSample]) {
        guard !samples.isEmpty else { return }
        var appliedPredictedCorrection = pendingPredictedDelta == .zero

        for sample in samples {
            var intents = recognizer.handle([sample])

            if !appliedPredictedCorrection {
                if let index = intents.firstIndex(where: { if case .move = $0 { return true } else { return false } }),
                   case .move(let delta) = intents[index] {
                    intents[index] = .move(Delta(delta.vector - pendingPredictedDelta.vector))
                    appliedPredictedCorrection = true
                }
            }

            guard !intents.isEmpty else { continue }
            intentSink?.handle(intents, timestamp: sample.timestamp, predicted: false)
        }

        // Whether or not a `.move` intent showed up to receive it, the correction has now either
        // been applied or gone stale (no cursor-move datagram this batch to carry it) — either
        // way it does not carry forward past this callback.
        pendingPredictedDelta = .zero
    }

    /// spec §4.2.1: "take the last predicted point, use ≤ 1 frame of extrapolation, blend 50 %,
    /// and mark the datagram `flags.predicted`". Only the single active primary touch is
    /// extrapolated — with two or more fingers down the gesture is scroll/pinch/swipe, not a
    /// cursor move, so prediction does not apply.
    private func emitPrediction(for touches: Set<UITouch>, event: UIEvent?) {
        guard touches.count == 1, let touch = touches.first,
              let predicted = event?.predictedTouches(for: touch)?.last else { return }

        let actual = touch.preciseLocation(in: self)
        let predictedPoint = predicted.preciseLocation(in: self)
        let extrapolated = Vector2(x: Double(predictedPoint.x - actual.x), y: Double(predictedPoint.y - actual.y))
        let blended = extrapolated * 0.5
        guard blended != .zero else { return }

        pendingPredictedDelta = pendingPredictedDelta + Delta(blended)
        intentSink?.handle([.move(Delta(blended))], timestamp: touch.timestamp, predicted: true)
    }

    // MARK: Accessibility (spec §4.8: "the surface has an accessibility label and custom actions
    // for click/right-click")

    public override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            [
                UIAccessibilityCustomAction(
                    name: String(localized: "Click", comment: "Accessibility custom action on the touchpad surface")
                ) { [weak self] _ in
                    self?.intentSink?.handle(
                        [.click(button: .left, kind: .tap, count: 1)],
                        timestamp: CACurrentMediaTime(),
                        predicted: false
                    )
                    return true
                },
                UIAccessibilityCustomAction(
                    name: String(localized: "Right-click", comment: "Accessibility custom action on the touchpad surface")
                ) { [weak self] _ in
                    self?.intentSink?.handle(
                        [.click(button: .right, kind: .tap, count: 1)],
                        timestamp: CACurrentMediaTime(),
                        predicted: false
                    )
                    return true
                },
            ]
        }
        set {} // UIKit requires the setter to exist to override the property; unused.
    }
}
