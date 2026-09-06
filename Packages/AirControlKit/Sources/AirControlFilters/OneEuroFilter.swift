import Foundation

/// One-Euro filter (Casiez, Pubil, Roussel 2012), spec §6.3:
///
/// `α(fc, Δt) = 1 / (1 + 1/(2π·fc·Δt))`, derivative low-pass filtered with `dCutoff`,
/// `fc = minCutoff + beta·|dx̂|`.
///
/// Deterministic and allocation-free; time is supplied by the caller (never reads a clock itself).
/// For the gyro engine (spec §4.3.4) this is applied to the *integrated angle*, not the raw rate —
/// see `GyroMapper`, which owns that composition.
public struct OneEuroFilter: Sendable {
    public var minCutoff: Double
    public var beta: Double
    public var dCutoff: Double

    private var xFilter = LowPassFilter()
    private var dxFilter = LowPassFilter()
    private var lastTime: TimeInterval?

    public init(minCutoff: Double, beta: Double, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    /// Filters one sample `x` taken at time `t` (seconds). The first call for a fresh filter (or
    /// after `reset()`) seeds the internal state and returns `x` unchanged.
    public mutating func filter(_ x: Double, t: TimeInterval) -> Double {
        guard let last = lastTime else {
            lastTime = t
            xFilter.seed(x)
            dxFilter.seed(0)
            return x
        }
        // Guard against non-increasing timestamps (duplicate/out-of-order samples): treat as an
        // infinitesimally small step rather than dividing by zero or going negative.
        let dt = Swift.max(t - last, 1e-6)
        lastTime = t

        let dx = (x - xFilter.lastValue) / dt
        let edx = dxFilter.filter(dx, alpha: Self.alpha(cutoff: dCutoff, dt: dt))
        let cutoff = minCutoff + beta * Swift.abs(edx)
        return xFilter.filter(x, alpha: Self.alpha(cutoff: Swift.max(cutoff, 1e-6), dt: dt))
    }

    /// Clears all history; the next `filter(_:t:)` call re-seeds as if this were a brand new filter.
    public mutating func reset() {
        lastTime = nil
        xFilter.reset()
        dxFilter.reset()
    }

    static func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1.0 / (2.0 * Double.pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }
}

/// Simple exponential low-pass filter shared by the value and derivative stages of `OneEuroFilter`.
private struct LowPassFilter {
    private(set) var lastValue: Double = 0
    private var hasValue = false

    mutating func seed(_ value: Double) {
        lastValue = value
        hasValue = true
    }

    mutating func filter(_ value: Double, alpha: Double) -> Double {
        guard hasValue else {
            seed(value)
            return value
        }
        let result = alpha * value + (1 - alpha) * lastValue
        lastValue = result
        return result
    }

    mutating func reset() {
        hasValue = false
        lastValue = 0
    }
}
