import Foundation
import Testing
@testable import AirControlProtocol

@Suite struct MotionFixedPointTests {
    @Test func encodesWholePoints() {
        #expect(MotionFixedPoint.encode(1.0) == 8)
        #expect(MotionFixedPoint.encode(-1.0) == -8)
        #expect(MotionFixedPoint.encode(0.0) == 0)
    }

    @Test func encodesEighthPointResolution() {
        #expect(MotionFixedPoint.encode(0.125) == 1)
        #expect(MotionFixedPoint.encode(0.25) == 2)
        #expect(MotionFixedPoint.encode(-0.125) == -1)
    }

    @Test func decodeIsTheExactInverseOfEncodeForRepresentableValues() {
        for eighths: Int16 in [-1000, -1, 0, 1, 12345, Int16.max, Int16.min] {
            let points = MotionFixedPoint.decode(eighths)
            #expect(MotionFixedPoint.encode(points) == eighths)
        }
    }

    @Test func saturatesRatherThanWrapsOnOverflow() {
        #expect(MotionFixedPoint.encode(100_000) == Int16.max)
        #expect(MotionFixedPoint.encode(-100_000) == Int16.min)
    }

    @Test func maxMagnitudeMatchesSpec() {
        // spec §3.5.2: "±4095.875 pt per datagram".
        #expect(MotionFixedPoint.maxMagnitudePoints == 4095.875)
    }

    @Test func nonFiniteInputEncodesToZero() {
        #expect(MotionFixedPoint.encode(.nan) == 0)
        #expect(MotionFixedPoint.encode(.infinity) == 0)
        #expect(MotionFixedPoint.encode(-.infinity) == 0)
    }

    @Test func roundsToNearestEighth() {
        // 0.06 pt rounds to 0/8, 0.07 pt rounds to 1/8 (0.0625 boundary).
        #expect(MotionFixedPoint.encode(0.06) == 0)
        #expect(MotionFixedPoint.encode(0.07) == 1)
    }
}
