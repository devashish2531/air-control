import Testing
@testable import AirMouseFilters

@Suite struct AccelerationCurveTests {
    // spec §5.4 sample table: base(s) for s = 1...10.
    static let expectedBase: [Double] = [0.60, 0.74, 0.91, 1.13, 1.39, 1.72, 2.12, 2.62, 3.24, 4.00]

    @Test(arguments: 1...10)
    func baseMatchesSpecTable(sensitivity: Int) {
        let computed = AccelerationCurve.base(sensitivity: Double(sensitivity))
        let expected = Self.expectedBase[sensitivity - 1]
        // The spec table rounds to 2 decimals; allow a hair more than half a rounding step.
        #expect(abs(computed - expected) < 0.006)
    }

    @Test func baseIsMonotonicIncreasingInSensitivity() {
        var last = AccelerationCurve.base(sensitivity: 1)
        for s in 2...10 {
            let value = AccelerationCurve.base(sensitivity: Double(s))
            #expect(value > last)
            last = value
        }
    }

    @Test func baseClampsBelowRange() {
        #expect(AccelerationCurve.base(sensitivity: -5) == AccelerationCurve.base(sensitivity: 1))
    }

    @Test func baseClampsAboveRange() {
        #expect(AccelerationCurve.base(sensitivity: 99) == AccelerationCurve.base(sensitivity: 10))
    }

    @Test func offProfileHasNoVelocityDependentAcceleration() {
        let curve = AccelerationCurve(sensitivity: 5, profile: .off)
        #expect(curve.accel(velocity: 0) == 1)
        #expect(curve.accel(velocity: 10_000) == 1)
    }

    @Test func accelAtZeroVelocityIsAlwaysOne() {
        for profile in AccelerationCurve.Profile.allCases {
            let curve = AccelerationCurve(sensitivity: 5, profile: profile)
            #expect(curve.accel(velocity: 0) == 1)
        }
    }

    @Test func accelAtReferenceVelocityMatchesFormula() {
        let curve = AccelerationCurve(sensitivity: 5, profile: .default, referenceVelocity: 1500)
        // accel(v_ref) = 1 + a·min(1,1)² = 1 + a
        #expect(abs(curve.accel(velocity: 1500) - (1 + 2.5)) < 1e-9)
    }

    @Test func accelSaturatesBeyondReferenceVelocity() {
        let curve = AccelerationCurve(sensitivity: 5, profile: .fast, referenceVelocity: 1500)
        let atRef = curve.accel(velocity: 1500)
        let beyond = curve.accel(velocity: 5000)
        #expect(atRef == beyond)
    }

    @Test func accelIsMonotonicBelowReferenceVelocity() {
        let curve = AccelerationCurve(sensitivity: 5, profile: .default, referenceVelocity: 1500)
        var last = curve.accel(velocity: 0)
        for v in stride(from: 100.0, through: 1500, by: 100) {
            let value = curve.accel(velocity: v)
            #expect(value >= last)
            last = value
        }
    }

    @Test func gyroSourceBypassesAccelerationEntirely() {
        let curve = AccelerationCurve(sensitivity: 10, profile: .fast)
        #expect(curve.gain(velocity: 10_000, isGyroSource: true) == 1.0)
    }

    @Test func applyToGyroSourceReturnsDeltaUnchanged() {
        let curve = AccelerationCurve(sensitivity: 10, profile: .fast)
        let delta = Delta(dx: 3, dy: -4)
        let result = curve.apply(delta, sampleInterval: 0.01, isGyroSource: true)
        #expect(result == delta)
    }

    @Test func firstDatagramOfBurstForcesAccelToOne() {
        let curve = AccelerationCurve(sensitivity: 5, profile: .fast)
        let delta = Delta(dx: 100, dy: 0) // would imply a huge velocity if not for the burst rule
        let result = curve.apply(delta, sampleInterval: 0.004, isFirstOfBurst: true)
        #expect(abs(result.dx - delta.dx * curve.base) < 1e-9)
    }

    @Test func applyScalesDeltaBySensitivityAndVelocity() {
        let curve = AccelerationCurve(sensitivity: 5, profile: .default, referenceVelocity: 1500)
        let delta = Delta(dx: 10, dy: 0)
        let sampleInterval = 0.01 // -> v = 1000 pt/s
        let result = curve.apply(delta, sampleInterval: sampleInterval)
        let expectedGain = curve.gain(velocity: 1000)
        #expect(abs(result.dx - 10 * expectedGain) < 1e-9)
    }

    @Test func sampleIntervalIsClampedToSpecRange() {
        let curve = AccelerationCurve(sensitivity: 5, profile: .default)
        let delta = Delta(dx: 10, dy: 0)
        // A sample interval far below 4ms should behave as if clamped to 4ms.
        let tooFast = curve.apply(delta, sampleInterval: 0.0001)
        let atFloor = curve.apply(delta, sampleInterval: 0.004)
        #expect(abs(tooFast.dx - atFloor.dx) < 1e-9)
    }
}
