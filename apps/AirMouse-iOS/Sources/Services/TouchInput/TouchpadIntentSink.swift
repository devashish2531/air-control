// Services/TouchInput/TouchpadIntentSink.swift
// Output boundary of the touch input engine (arch §3.2 "TouchInputView ... emits GestureEvents:
// motion deltas → MotionPublisher, clicks/scroll phases/keys/modifiers → ConnectionManager").
// `TouchpadUIView` (this directory) is the sole caller; `TouchpadController`
// (Features/Touchpad, this agent's own directory too) is the concrete conformer that fans a
// batch out to `MotionPublisher`/`ControlMessageSink`/`HapticsService`.

import Foundation
import AirMouseFilters

/// Receives one batch of `TouchpadIntent`s per `touchesBegan/Moved/Ended/Cancelled` callback (or
/// per `advanceTime(to:)` tick that produced intents with no new touch — long-press timeout,
/// tap-and-drag window closing, drag-lock timeout; spec §4.2.3).
///
/// `predicted` is `true` only for the synthetic extrapolated `.move` batch derived from
/// `predictedTouches(for:)` when the Prediction Labs flag is on (spec §4.2.1, §3.5.6): "the next
/// real frame subtracts the predicted contribution so the integral stays exact" — `TouchpadUIView`
/// performs that subtraction itself before calling back with `predicted: false`, so the sink only
/// needs to tag the datagram's `flags.predicted` bit differently by this flag, never re-derive it.
@MainActor
public protocol TouchpadIntentSink: AnyObject {
    /// `timestamp` is the originating `TouchSample`'s timestamp (or, for a purely time-driven
    /// batch from `advanceTime(to:)`, the tick's own clock reading) — the client monotonic clock
    /// reading `MotionPublisher` encodes into the wire's `timestamp` field (spec §3.5.2).
    func handle(_ intents: [TouchpadIntent], timestamp: TimeInterval, predicted: Bool)
}

/// Stand-in so `TouchpadScreen()`'s zero-argument entry point keeps compiling before
/// `TouchpadFeature.make(environment:motion:controlSink:)` wires a real `TouchpadController`.
/// Mirrors the `NoOp*` naming used across the app for cross-module default slots.
@MainActor
public final class NoOpTouchpadIntentSink: TouchpadIntentSink {
    public init() {}
    public func handle(_ intents: [TouchpadIntent], timestamp: TimeInterval, predicted: Bool) {}
}
