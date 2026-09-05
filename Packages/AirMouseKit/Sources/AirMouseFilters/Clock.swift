import Foundation

/// A source of monotonic-ish time, injected everywhere in this module so algorithms are
/// deterministic and never call `Date()`/`ProcessInfo.systemUptime` themselves (spec §6.3, §4.3.4).
///
/// Conforming types only need to promise the value is non-decreasing for a single instance;
/// the unit is seconds so it composes directly with `TimeInterval`-based APIs like
/// `OneEuroFilter.filter(_:t:)`.
public protocol Clock: Sendable {
    /// Seconds since an arbitrary but fixed origin for this clock instance.
    func now() -> TimeInterval
}

/// A `Clock` for tests: time only moves when told to, so a whole scenario (gyro filter step
/// response, momentum decay sequence, gesture timing edge case) can be scripted deterministically.
public final class ManualClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var time: TimeInterval

    public init(start: TimeInterval = 0) {
        self.time = start
    }

    public func now() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return time
    }

    /// Moves the clock forward by `delta` seconds (must be >= 0) and returns the new time.
    @discardableResult
    public func advance(by delta: TimeInterval) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        time += delta
        return time
    }

    /// Sets the clock to an absolute time.
    public func set(_ t: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        time = t
    }
}
