// Features/Diagnostics/DiagnosticsModel.swift
// Latency HUD data model per arch §8 "Diagnostics HUD": fed at 4 Hz by the Connection agent's
// `RTTEstimator` snapshot and the Motion agent's probe RTT/loss/channel/in-flight counters. This
// module does not compute any of those numbers itself (no networking/motion code) — it only
// receives already-computed samples through `DiagnosticsReceiving` and keeps a short rolling
// history for the HUD and log/export.

import Foundation
import Observation

/// Which channel motion datagrams are currently using (spec §3.5.8 / §9 E-UDP-FALLBACK).
public enum MotionChannel: String, Sendable, Equatable {
    case udp
    case tcpFallback
}

/// One diagnostics tick. All fields are optional because a given moment may not have a fresh
/// value for every metric (e.g. no RTT sample yet while `Connecting`).
public struct LatencySample: Sendable, Equatable {
    public var timestamp: Date
    public var rttMillisP50: Double?
    public var rttMillisP95: Double?
    public var probeRTTMillis: Double?
    public var oneWayEstimateMillis: Double?
    public var lossPercent: Double?
    public var channel: MotionChannel
    public var inFlightDatagrams: Int

    public init(
        timestamp: Date = Date(),
        rttMillisP50: Double? = nil,
        rttMillisP95: Double? = nil,
        probeRTTMillis: Double? = nil,
        oneWayEstimateMillis: Double? = nil,
        lossPercent: Double? = nil,
        channel: MotionChannel = .udp,
        inFlightDatagrams: Int = 0
    ) {
        self.timestamp = timestamp
        self.rttMillisP50 = rttMillisP50
        self.rttMillisP95 = rttMillisP95
        self.probeRTTMillis = probeRTTMillis
        self.oneWayEstimateMillis = oneWayEstimateMillis
        self.lossPercent = lossPercent
        self.channel = channel
        self.inFlightDatagrams = inFlightDatagrams
    }
}

/// The narrow surface the Connection/Motion agents publish samples through. Kept separate from
/// `DiagnosticsModel` so a mock/preview can feed samples without depending on `@Observable`.
@MainActor
public protocol DiagnosticsReceiving: AnyObject {
    func ingest(_ sample: LatencySample)
}

/// `@Observable` model backing the Latency HUD overlay and the Diagnostics log viewer stub.
/// Keeps a bounded ring of recent samples (60 — 15 s at the spec's 4 Hz feed rate) for the HUD
/// sparkline and "Export diagnostics…" (arch §8, `diagnostics/1`).
@MainActor
@Observable
public final class DiagnosticsModel: DiagnosticsReceiving {
    public private(set) var latest: LatencySample?
    public private(set) var history: [LatencySample] = []

    /// `sendMotion`/`sendProbe` failures the Connection agent's sinks would otherwise swallow with
    /// `try?`, keyed by a short error-kind label (e.g. "channelClosed"). Previously these vanished
    /// silently — `TouchpadDebugMotionLabel`'s `sentDatagramCount` only proves `sendMotion(_:)` was
    /// *called*, not that anything reached the network — so a session stuck unable to open its UDP
    /// channel looked identical, from this counter's perspective, to one working perfectly. See
    /// `ConnectionMotionSink.sendMotion(_:)`.
    public private(set) var motionSendFailureCounts: [String: Int] = [:]

    private let maxHistory: Int

    public init(maxHistory: Int = 60) {
        self.maxHistory = maxHistory
    }

    public func ingest(_ sample: LatencySample) {
        latest = sample
        history.append(sample)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
    }

    /// Records one swallowed motion/probe send failure by kind, for `motionSendFailureCounts`.
    public func recordMotionSendFailure(kind: String) {
        motionSendFailureCounts[kind, default: 0] += 1
    }

    public func reset() {
        latest = nil
        history.removeAll()
        motionSendFailureCounts.removeAll()
    }
}
