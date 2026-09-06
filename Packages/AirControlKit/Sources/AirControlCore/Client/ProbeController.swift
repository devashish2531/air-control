import Foundation
import AirControlProtocol

/// UDP probe / TCP-fallback heuristic (spec §3.5.8), driven purely by outcome events so it is
/// testable with a fake clock — no timers or `Network` calls live here (arch §3.1).
///
/// | Rule | Value |
/// |---|---|
/// | Probe interval, connected | 250 ms (4 Hz) |
/// | Probe window | last 12 probes (3 s) |
/// | Enter fallback | ≥ 11 of 12 unanswered **and** a `pong` received in the last 1 s (TCP healthy) — or the first 8 probes after connect all unanswered (2 s) |
/// | In fallback | probes continue at 1 Hz |
/// | Exit fallback | 5 consecutive probes answered |
public struct ProbeController: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        case normal
        case fallback
    }

    public private(set) var mode: Mode = .normal

    /// Ring of the last `probeWindowSize` (12) outcomes, oldest first; `true` = answered.
    private var outcomes: [Bool] = []
    /// Total probes recorded since the last `reset()` (connect / reconnect), used for the
    /// "first 8 probes after connect" burst rule; not reset when entering/exiting fallback so the
    /// burst rule only ever applies once per connection, matching "after connect".
    private var probesSinceConnect: Int = 0
    /// Consecutive answered probes since the most recent entry into `.fallback`.
    private var consecutiveAnsweredInFallback: Int = 0

    public init() {}

    /// Probe cadence for the current mode (spec §3.5.8: 4 Hz connected / 1 Hz in fallback).
    public var probeInterval: TimeInterval {
        mode == .fallback ? 1.0 : Double(ProtocolConstants.probeIntervalMs) / 1000.0
    }

    /// Feeds one probe's outcome through the heuristic.
    ///
    /// - Parameters:
    ///   - answered: whether the host's echo (`flags.echo`) arrived before this probe expired.
    ///   - pongSeenWithinLastSecond: whether a `heartbeat`/`pong` round-trip completed within the
    ///     last second (spec's "TCP healthy" condition, required for the ≥11-of-12 rule but not
    ///     the initial-burst rule).
    /// - Returns: the resulting mode (also available afterward as `mode`).
    @discardableResult
    public mutating func recordProbeOutcome(answered: Bool, pongSeenWithinLastSecond: Bool) -> Mode {
        probesSinceConnect += 1
        outcomes.append(answered)
        if outcomes.count > ProtocolConstants.probeWindowSize {
            outcomes.removeFirst(outcomes.count - ProtocolConstants.probeWindowSize)
        }

        switch mode {
        case .normal:
            evaluateFallbackEntry(pongSeenWithinLastSecond: pongSeenWithinLastSecond)
        case .fallback:
            evaluateFallbackExit(answered: answered)
        }
        return mode
    }

    private mutating func evaluateFallbackEntry(pongSeenWithinLastSecond: Bool) {
        // spec: "the first 8 probes after connect all unanswered (2 s)".
        if probesSinceConnect == ProtocolConstants.probeFallbackInitialUnansweredBurst,
           outcomes.suffix(ProtocolConstants.probeFallbackInitialUnansweredBurst).allSatisfy({ !$0 }) {
            enterFallback()
            return
        }
        // spec: "≥ 11 of 12 unanswered (≥ 90 %) and a pong received in the last 1 s".
        guard outcomes.count == ProtocolConstants.probeWindowSize else { return }
        let lostCount = outcomes.filter { !$0 }.count
        if lostCount >= ProtocolConstants.probeFallbackLostThreshold && pongSeenWithinLastSecond {
            enterFallback()
        }
    }

    private mutating func evaluateFallbackExit(answered: Bool) {
        if answered {
            consecutiveAnsweredInFallback += 1
            if consecutiveAnsweredInFallback >= ProtocolConstants.probeRecoveryAnsweredThreshold {
                mode = .normal
                outcomes.removeAll()
                consecutiveAnsweredInFallback = 0
            }
        } else {
            consecutiveAnsweredInFallback = 0
        }
    }

    private mutating func enterFallback() {
        mode = .fallback
        consecutiveAnsweredInFallback = 0
        outcomes.removeAll()
    }

    /// Resets all counters (spec: a fresh `sessionKey`/connection starts the "since connect"
    /// clock over, and forgets the outcome window).
    public mutating func reset() {
        mode = .normal
        outcomes.removeAll()
        probesSinceConnect = 0
        consecutiveAnsweredInFallback = 0
    }
}
