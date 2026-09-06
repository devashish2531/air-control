import Testing
@testable import AirControlCore

@Suite struct HeartbeatClockTests {
    @Test func noSamplesYieldsNilStats() {
        let clock = HeartbeatClock()
        #expect(clock.rttP50 == nil)
        #expect(clock.rttP95 == nil)
        #expect(clock.clockOffset == nil)
    }

    @Test func singleRoundTripComputesExpectedRTT() {
        var clock = HeartbeatClock()
        // t1=0, t2=1000 (host receives 1ms later), t3=1000 (host sends immediately), t4=2000 (client
        // receives 1ms later): RTT = t4 - t1 - (t3 - t2) = 2000 - 0 - 0 = 2000us = 2ms.
        clock.recordRoundTrip(t1: 0, t2: 1000, t3: 1000, t4: 2000)
        #expect(clock.rttP50 == 0.002)
    }

    @Test func percentilesOverMultipleSamples() {
        var clock = HeartbeatClock()
        // RTTs (us): 1000, 2000, 3000, 4000, 5000 -> seconds: .001...005
        let rtts: [Int64] = [1000, 2000, 3000, 4000, 5000]
        for rtt in rtts {
            clock.recordRoundTrip(t1: 0, t2: 0, t3: 0, t4: rtt)
        }
        #expect(clock.rttP50 == 0.003)
        #expect(clock.rttP95 != nil)
    }

    @Test func ringBufferCapsAtThirtyTwoSamples() {
        var clock = HeartbeatClock()
        for index in 0..<40 {
            clock.recordRoundTrip(t1: 0, t2: 0, t3: 0, t4: Int64(index) * 1000)
        }
        #expect(clock.rttSamplesSeconds.count == 32)
        // Oldest 8 samples (indices 0...7) should have been evicted; the ring should start at index 8.
        #expect(clock.rttSamplesSeconds.first == 0.008)
    }

    @Test func offsetRingCapsAtEightSamples() {
        var clock = HeartbeatClock()
        for index in 0..<20 {
            clock.recordRoundTrip(t1: Int64(index) * 100, t2: 0, t3: 0, t4: 0)
        }
        #expect(clock.offsetSamplesSeconds.count == 8)
    }

    @Test func clockOffsetMedianOfLastEightPongs() {
        var clock = HeartbeatClock()
        // offset = ((t2-t1)+(t3-t4))/2. Use t1=0,t4=0 so offset = (t2+t3)/2.
        for offsetMicros in [1000, 2000, 3000] {
            clock.recordRoundTrip(t1: 0, t2: Int64(offsetMicros), t3: Int64(offsetMicros), t4: 0)
        }
        #expect(clock.clockOffset == 0.002)
    }

    @Test func oneWayMotionLatencyUsesClockOffset() {
        var clock = HeartbeatClock()
        // theta = 0 (symmetric round trip).
        clock.recordRoundTrip(t1: 0, t2: 0, t3: 0, t4: 0)
        // oneWay = (hostTs - theta) - clientTs.
        let oneWay = clock.oneWayMotionLatency(motionClientTs: 0, motionHostTs: 5000)
        #expect(oneWay == 0.005)
    }

    @Test func oneWayMotionLatencyNilWithoutSamples() {
        let clock = HeartbeatClock()
        #expect(clock.oneWayMotionLatency(motionClientTs: 0, motionHostTs: 1000) == nil)
    }
}
