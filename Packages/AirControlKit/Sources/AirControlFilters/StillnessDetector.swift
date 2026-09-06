import Foundation

/// Auto-freeze detector for the gyro engine (spec §4.3.5): "Auto-freeze: if the standard deviation
/// of `|userAcceleration|` over the last 500 ms < 0.02 g **and** `|ω| < dz`, output is forced to 0
/// (phone on a table → 0 px creep)."
///
/// This type only tracks the acceleration-magnitude half of that condition (a rolling 500 ms
/// window's standard deviation); `GyroMapper` combines it with the dead-zone condition.
public struct StillnessDetector: Sendable {
    public var window: TimeInterval
    public var threshold: Double

    private var samples: [(t: TimeInterval, magnitude: Double)] = []

    public init(window: TimeInterval = 0.5, threshold: Double = 0.02) {
        self.window = window
        self.threshold = threshold
    }

    /// Feeds one `|userAcceleration|` sample (in g) at `timestamp` and reports whether the window is
    /// "quiet" (standard deviation below `threshold`). Returns `false` until enough history has
    /// accumulated to judge.
    @discardableResult
    public mutating func update(magnitude: Double, timestamp: TimeInterval) -> Bool {
        samples.append((timestamp, magnitude))
        samples.removeAll { timestamp - $0.t > window }
        guard samples.count >= 2 else { return false }
        let mean = samples.reduce(0) { $0 + $1.magnitude } / Double(samples.count)
        let variance = samples.reduce(0) { $0 + ($1.magnitude - mean) * ($1.magnitude - mean) } / Double(samples.count)
        return variance.squareRoot() < threshold
    }

    public mutating func reset() {
        samples.removeAll()
    }
}
