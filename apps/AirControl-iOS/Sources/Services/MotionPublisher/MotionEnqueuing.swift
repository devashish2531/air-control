// Services/MotionPublisher/MotionEnqueuing.swift
// Input boundary of `MotionPublisher`, seen from `TouchpadController`/`GyroEngine`. A protocol
// (rather than requiring the concrete `MotionPublisher` actor everywhere) so `TouchpadController`
// and its tests can depend on the narrow surface they actually call, and so
// `TouchpadScreen`'s zero-argument preview/default path has a trivial no-op to construct.
//
// Every method takes raw point deltas already in the recognizer's coordinate space (spec §4.2.4:
// "the client sends raw finger deltas in points ... gain and acceleration are applied on the
// host") — no scaling happens on this side of the boundary.

import Foundation
import AirControlProtocol

public protocol MotionEnqueuing: Sendable {
    /// Single-finger cursor move / gyro delta (spec §3.5.2 `dx`/`dy`).
    func enqueue(dx: Double, dy: Double, flags: MotionFlags, source: MotionSource, timestamp: TimeInterval) async
    /// Two-finger scroll delta (spec §3.5.2 `scrollX`/`scrollY`).
    func enqueueScroll(dx: Double, dy: Double, flags: MotionFlags, source: MotionSource, timestamp: TimeInterval) async
}

/// Default stand-in until `TouchpadFeature.make(environment:motion:controlSink:)` injects the
/// real `MotionPublisher` actor.
public struct NoOpMotionEnqueuer: MotionEnqueuing {
    public init() {}
    public func enqueue(dx: Double, dy: Double, flags: MotionFlags, source: MotionSource, timestamp: TimeInterval) async {}
    public func enqueueScroll(dx: Double, dy: Double, flags: MotionFlags, source: MotionSource, timestamp: TimeInterval) async {}
}

/// Snapshot of `MotionPublisher`'s internal counters (spec §5.4 / arch §5.4 backpressure
/// bookkeeping), for tests and for feeding `DiagnosticsModel` (arch §8 Diagnostics HUD).
/// `DiagnosticsModel`'s `LatencySample` (Features/Diagnostics, owned by another agent) has no
/// dedicated "samples/s" or "coalesced count" fields, so `MotionPublisher` reports this richer
/// shape on its own `nonisolated` accessor in addition to feeding what `LatencySample` does have
/// (`inFlightDatagrams`, `channel`) through `DiagnosticsReceiving` — see `MotionPublisher`'s doc
/// comment for the full deviation note.
public struct MotionPublisherStats: Sendable, Equatable {
    public var samplesPerSecond: Double
    public var coalescedCount: Int
    public var droppedDatagramCount: Int
    public var sentDatagramCount: Int
    public var queuedDatagramCount: Int

    public init(
        samplesPerSecond: Double = 0,
        coalescedCount: Int = 0,
        droppedDatagramCount: Int = 0,
        sentDatagramCount: Int = 0,
        queuedDatagramCount: Int = 0
    ) {
        self.samplesPerSecond = samplesPerSecond
        self.coalescedCount = coalescedCount
        self.droppedDatagramCount = droppedDatagramCount
        self.sentDatagramCount = sentDatagramCount
        self.queuedDatagramCount = queuedDatagramCount
    }
}
