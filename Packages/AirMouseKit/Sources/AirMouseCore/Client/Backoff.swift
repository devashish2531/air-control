import Foundation
import AirMouseProtocol

/// Reconnect backoff schedule (spec §4.5.2, §11.3): "attempts at 250 ms, 500 ms, 1 s, 2 s, 4 s,
/// 4 s… (cap 4 s) with ±20 % jitter, indefinitely while foregrounded". A pure value type: the
/// caller supplies its own jitter sample (a `Double` in `-1...1`) so tests are deterministic
/// without this type owning an RNG.
public struct Backoff: Sendable, Equatable {
    /// The step table before jitter, seconds (spec §11.3: 250, 500, 1000, 2000, 4000 ms).
    public static var stepsSeconds: [TimeInterval] {
        ProtocolConstants.reconnectBackoffStepsMs.map { Double($0) / 1000.0 }
    }
    /// spec §11.3: "±20 %".
    public static let jitterFraction = ProtocolConstants.reconnectBackoffJitterFraction
    /// spec §4.5.1 / §11.3: "Reconnect give-up (foreground) | 10 min".
    public static let giveUpSeconds = TimeInterval(ProtocolConstants.reconnectGiveUpForegroundSeconds)

    /// How many delays have been produced so far (0-based index into `stepsSeconds`, clamped at
    /// the last step — "4 s… (cap 4 s)").
    public private(set) var attemptIndex: Int

    public init(attemptIndex: Int = 0) {
        self.attemptIndex = attemptIndex
    }

    /// The un-jittered base delay for a given attempt index (0-based), clamped to the last step.
    public static func baseDelay(attemptIndex: Int) -> TimeInterval {
        let steps = stepsSeconds
        let clampedIndex = min(max(attemptIndex, 0), steps.count - 1)
        return steps[clampedIndex]
    }

    /// Applies the spec's ±20 % jitter to the base delay for `attemptIndex`, given a caller-supplied
    /// sample `unitJitter` in `-1...1` (typically `Double.random(in: -1...1)` in production; a fixed
    /// sequence in tests). Values outside `-1...1` are clamped.
    public static func jitteredDelay(attemptIndex: Int, unitJitter: Double) -> TimeInterval {
        let base = baseDelay(attemptIndex: attemptIndex)
        let clampedJitter = min(max(unitJitter, -1), 1)
        return base * (1 + clampedJitter * jitterFraction)
    }

    /// Returns the jittered delay for the current attempt and advances `attemptIndex`.
    @discardableResult
    public mutating func nextDelay(unitJitter: Double = 0) -> TimeInterval {
        let delay = Self.jitteredDelay(attemptIndex: attemptIndex, unitJitter: unitJitter)
        attemptIndex += 1
        return delay
    }

    /// Resets the schedule to its first step (spec: a successful connect resets backoff).
    public mutating func reset() {
        attemptIndex = 0
    }

    /// Whether `elapsedSinceReconnectingBegan` has passed the foreground give-up threshold
    /// (spec §4.5.1 / §11.3: "10 min").
    public static func hasGivenUp(elapsedSinceReconnectingBegan elapsed: TimeInterval) -> Bool {
        elapsed >= giveUpSeconds
    }
}
