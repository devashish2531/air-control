import Foundation

/// RTT/latency statistics from `heartbeat`/`pong` round trips (spec §3.4.6, §8.2).
///
/// `RTT = t4 − t1 − (t3 − t2)` where `t1` = client send time, `t2` = host receive time, `t3` =
/// host send time, `t4` = client receive time (all monotonic microseconds). Keeps a 32-sample
/// ring for the HUD's p50/p95 (spec §3.4.6: "the client keeps a 32-sample ring for the HUD") and
/// an 8-sample ring of clock-offset estimates `θ = ((t2 − t1) + (t3 − t4)) / 2` (spec §8.2: "from
/// the most recent 8 pongs (median)").
public struct HeartbeatClock: Sendable, Equatable {
    /// spec §3.4.6: "32-sample ring".
    public static let rttRingSize = 32
    /// spec §8.2: "the most recent 8 pongs (median)".
    public static let offsetSampleCount = 8

    /// RTT samples in seconds, oldest first, capped at `rttRingSize`.
    public private(set) var rttSamplesSeconds: [Double] = []
    /// Clock-offset samples in seconds, oldest first, capped at `offsetSampleCount`.
    public private(set) var offsetSamplesSeconds: [Double] = []

    public init() {}

    /// Records one `heartbeat` → `pong` round trip. All timestamps are monotonic microseconds
    /// (`Int64`, matching `Heartbeat.t1`/`Pong.t2`/`Pong.t3` and the client's own receive time).
    public mutating func recordRoundTrip(t1: Int64, t2: Int64, t3: Int64, t4: Int64) {
        let rttMicros = Double(t4 - t1 - (t3 - t2))
        appendCapped(&rttSamplesSeconds, rttMicros / 1_000_000, limit: Self.rttRingSize)
        let offsetMicros = Double((t2 - t1) + (t3 - t4)) / 2.0
        appendCapped(&offsetSamplesSeconds, offsetMicros / 1_000_000, limit: Self.offsetSampleCount)
    }

    private func appendCapped(_ array: inout [Double], _ value: Double, limit: Int) {
        array.append(value)
        if array.count > limit {
            array.removeFirst(array.count - limit)
        }
    }

    /// Median RTT over the ring, or `nil` if no samples yet.
    public var rttP50: TimeInterval? { percentile(rttSamplesSeconds, 0.5) }
    /// 95th percentile RTT over the ring, or `nil` if no samples yet.
    public var rttP95: TimeInterval? { percentile(rttSamplesSeconds, 0.95) }
    /// Median of the last 8 per-pong clock-offset estimates (spec §8.2's `θ`), or `nil`.
    public var clockOffset: TimeInterval? { percentile(offsetSamplesSeconds, 0.5) }

    /// Nearest-rank percentile over a copy of `samples`, sorted ascending. `p` in `0...1`.
    private func percentile(_ samples: [Double], _ p: Double) -> Double? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count) * p).rounded(.down))))
        return sorted[index]
    }

    /// spec §8.2: "for the latest `pong.motion` pair, `oneWay = (motion.hostTs − θ) − motion.clientTs`".
    /// Returns `nil` until at least one clock-offset sample exists.
    public func oneWayMotionLatency(motionClientTs: Int64, motionHostTs: Int64) -> TimeInterval? {
        guard let theta = clockOffset else { return nil }
        let hostTsSeconds = Double(motionHostTs) / 1_000_000
        let clientTsSeconds = Double(motionClientTs) / 1_000_000
        return (hostTsSeconds - theta) - clientTsSeconds
    }
}
