import Foundation

/// A point-in-time snapshot of one session's health, for the Latency HUD / Diagnostics window
/// (spec §8.2).
public struct SessionStats: Sendable, Equatable {
    public var rttP50: TimeInterval?
    public var rttP95: TimeInterval?
    /// Probe datagram loss percentage over the current probe window (spec §3.5.8: last 12
    /// probes), `0...100`.
    public var lossPercent: Double
    /// Motion datagrams accepted per second, most recent 1 s window.
    public var motionRatePerSecond: Double
    /// Whether the session is currently on the TCP motion-batch fallback path (spec §3.5.8).
    public var isFallbackEngaged: Bool
    /// Estimated one-way motion latency (spec §8.2), if a clock offset estimate is available.
    public var oneWayMotionLatency: TimeInterval?

    public init(
        rttP50: TimeInterval? = nil,
        rttP95: TimeInterval? = nil,
        lossPercent: Double = 0,
        motionRatePerSecond: Double = 0,
        isFallbackEngaged: Bool = false,
        oneWayMotionLatency: TimeInterval? = nil
    ) {
        self.rttP50 = rttP50
        self.rttP95 = rttP95
        self.lossPercent = lossPercent
        self.motionRatePerSecond = motionRatePerSecond
        self.isFallbackEngaged = isFallbackEngaged
        self.oneWayMotionLatency = oneWayMotionLatency
    }
}

/// Accumulates the raw counters `SessionStats` snapshots are computed from. A plain mutable value
/// type (arch §3.1: no actors in the kit) — the owning actor (`ClientSession`/`HostSession`, or an
/// app's Diagnostics window) holds one `var` and calls `snapshot(now:)` at whatever cadence it
/// likes (spec §8.2: HUD over the last 2 s; Diagnostics window at 4 Hz).
public struct SessionStatsCollector: Sendable {
    private var heartbeat = HeartbeatClock()
    private var probe = ProbeController()
    /// Motion-datagram-accepted timestamps (seconds) within the last second, oldest first.
    private var recentMotionTimestamps: [TimeInterval] = []

    public init() {}

    public mutating func recordHeartbeatRoundTrip(t1: Int64, t2: Int64, t3: Int64, t4: Int64) {
        heartbeat.recordRoundTrip(t1: t1, t2: t2, t3: t3, t4: t4)
    }

    @discardableResult
    public mutating func recordProbeOutcome(answered: Bool, pongSeenWithinLastSecond: Bool) -> ProbeController.Mode {
        probe.recordProbeOutcome(answered: answered, pongSeenWithinLastSecond: pongSeenWithinLastSecond)
    }

    public mutating func recordMotionAccepted(now: TimeInterval) {
        recentMotionTimestamps.append(now)
        recentMotionTimestamps.removeAll { now - $0 > 1.0 }
    }

    /// Builds a snapshot as of `now` (seconds, same clock as `recordMotionAccepted`'s `now`).
    public func snapshot(now: TimeInterval, motionClientTs: Int64? = nil, motionHostTs: Int64? = nil) -> SessionStats {
        let oneWay: TimeInterval?
        if let motionClientTs, let motionHostTs {
            oneWay = heartbeat.oneWayMotionLatency(motionClientTs: motionClientTs, motionHostTs: motionHostTs)
        } else {
            oneWay = nil
        }
        let recentCount = recentMotionTimestamps.filter { now - $0 <= 1.0 }.count
        return SessionStats(
            rttP50: heartbeat.rttP50,
            rttP95: heartbeat.rttP95,
            lossPercent: 0,
            motionRatePerSecond: Double(recentCount),
            isFallbackEngaged: probe.mode == .fallback,
            oneWayMotionLatency: oneWay
        )
    }

    public var probeMode: ProbeController.Mode { probe.mode }
}
