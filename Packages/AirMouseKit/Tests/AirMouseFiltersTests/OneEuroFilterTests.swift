import Testing
@testable import AirMouseFilters

@Suite struct OneEuroFilterTests {
    @Test func firstSamplePassesThroughUnchanged() {
        var f = OneEuroFilter(minCutoff: 1.0, beta: 0.0, dCutoff: 1.0)
        #expect(f.filter(3.14, t: 0) == 3.14)
    }

    @Test func constantSignalIsUnchangedAtSteadyState() {
        var f = OneEuroFilter(minCutoff: 1.0, beta: 0.0, dCutoff: 1.0)
        var last = 0.0
        for i in 0..<50 {
            last = f.filter(5.0, t: Double(i) * 0.01)
        }
        #expect(abs(last - 5.0) < 1e-9)
    }

    @Test func higherMinCutoffTracksStepFaster() {
        // A bigger minCutoff means less smoothing, so after a step the filtered value should be
        // closer to the new value after the same number of samples.
        var loose = OneEuroFilter(minCutoff: 10.0, beta: 0.0, dCutoff: 1.0)
        var tight = OneEuroFilter(minCutoff: 0.5, beta: 0.0, dCutoff: 1.0)
        _ = loose.filter(0, t: 0)
        _ = tight.filter(0, t: 0)
        var looseValue = 0.0
        var tightValue = 0.0
        for i in 1...5 {
            let t = Double(i) * 0.01
            looseValue = loose.filter(1.0, t: t)
            tightValue = tight.filter(1.0, t: t)
        }
        #expect(looseValue > tightValue)
    }

    @Test func betaIncreasesResponsivenessDuringFastMotion() {
        // Two filters with identical minCutoff but different beta, fed a fast ramp: the one with
        // higher beta should track closer to the raw ramp (less lag) once the derivative estimate
        // has caught up.
        var lowBeta = OneEuroFilter(minCutoff: 0.5, beta: 0.0, dCutoff: 1.0)
        var highBeta = OneEuroFilter(minCutoff: 0.5, beta: 5.0, dCutoff: 1.0)
        var t = 0.0
        var x = 0.0
        var lowLast = 0.0
        var highLast = 0.0
        for _ in 0..<40 {
            lowLast = lowBeta.filter(x, t: t)
            highLast = highBeta.filter(x, t: t)
            t += 0.01
            x += 1.0 // 100 units/s ramp
        }
        let target = x - 1.0 // value at final t used for the last filter call above
        #expect(abs(target - highLast) < abs(target - lowLast))
    }

    @Test func resetClearsHistory() {
        var f = OneEuroFilter(minCutoff: 1.0, beta: 0.0, dCutoff: 1.0)
        _ = f.filter(0, t: 0)
        _ = f.filter(10, t: 0.01)
        f.reset()
        // Post-reset, the next sample should pass through unchanged again (fresh seed).
        #expect(f.filter(42, t: 100) == 42)
    }

    @Test func nonPositiveDtDoesNotCrashOrProduceNaN() {
        var f = OneEuroFilter(minCutoff: 1.0, beta: 1.0, dCutoff: 1.0)
        _ = f.filter(0, t: 0)
        let result = f.filter(1, t: 0) // same timestamp as previous sample
        #expect(result.isFinite)
    }

    @Test func alphaApproachesOneAsCutoffGrowsLarge() {
        // spec §6.3: α(fc, Δt) = 1 / (1 + 1/(2π·fc·Δt)); as fc → ∞, α → 1 (no smoothing).
        let alpha = OneEuroFilter.alpha(cutoff: 1_000_000, dt: 0.01)
        #expect(alpha > 0.999)
    }

    @Test func alphaApproachesZeroAsCutoffShrinks() {
        let alpha = OneEuroFilter.alpha(cutoff: 1e-6, dt: 0.01)
        #expect(alpha < 0.001)
    }

    // MARK: Gyro acceptance test (spec §4.3.4 / FR-GY-005)

    @Test func gyroCutoffAndLagBoundAt20DegreesPerSecond() {
        // "at ≥ 20 °/s the effective cutoff is ≥ 20 Hz, i.e. added lag ≤ 8 ms even at maximum
        // smoothing." beta = 1.0 Hz per (°/s) converted to Hz per rad/s (as GyroMapper does),
        // minCutoff at slider 10 (max smoothing, 0.5 Hz).
        let betaRadPerSec = 1.0 * (180.0 / Double.pi)
        let minCutoff = GyroMapper.minCutoff(forSlider: 10) // max smoothing
        let omegaDegPerSec = 20.0
        let omegaRadPerSec = omegaDegPerSec * Double.pi / 180.0

        let cutoff = minCutoff + betaRadPerSec * omegaRadPerSec
        #expect(cutoff >= 20.0 - 1e-9)

        let tau = 1.0 / (2 * Double.pi * cutoff)
        let lagSeconds = tau
        #expect(lagSeconds <= 0.008 + 1e-9)
    }

    @Test func oneEuroFilterConvergesToTrueRateUnderSustainedRotation() {
        // Feed the filter an integrated angle growing at a constant 20°/s (converted to radians)
        // and check the per-sample delta converges to the true per-sample angle increment, i.e. the
        // filter doesn't introduce steady-state bias.
        let omegaRadPerSec = 20.0 * Double.pi / 180.0
        let betaRadPerSec = 1.0 * (180.0 / Double.pi)
        var filter = OneEuroFilter(minCutoff: GyroMapper.minCutoff(forSlider: 10), beta: betaRadPerSec, dCutoff: 1.0)
        let dt = 0.01
        var theta = 0.0
        var lastFiltered = filter.filter(theta, t: 0)
        var lastDelta = 0.0
        for i in 1...300 {
            theta += omegaRadPerSec * dt
            let filtered = filter.filter(theta, t: Double(i) * dt)
            lastDelta = filtered - lastFiltered
            lastFiltered = filtered
        }
        let expectedDelta = omegaRadPerSec * dt
        #expect(abs(lastDelta - expectedDelta) / expectedDelta < 0.05)
    }
}
