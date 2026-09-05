import Testing
@testable import AirMouseCore

@Suite struct SessionStatsCollectorTests {
    @Test func snapshotStartsEmpty() {
        let collector = SessionStatsCollector()
        let snapshot = collector.snapshot(now: 0)
        #expect(snapshot.rttP50 == nil)
        #expect(snapshot.isFallbackEngaged == false)
        #expect(snapshot.motionRatePerSecond == 0)
    }

    @Test func motionRateCountsWithinOneSecondWindow() {
        var collector = SessionStatsCollector()
        collector.recordMotionAccepted(now: 0.0)
        collector.recordMotionAccepted(now: 0.5)
        collector.recordMotionAccepted(now: 0.9)
        let snapshot = collector.snapshot(now: 1.0)
        #expect(snapshot.motionRatePerSecond == 3)
        let laterSnapshot = collector.snapshot(now: 2.0)
        #expect(laterSnapshot.motionRatePerSecond == 0)
    }

    @Test func fallbackEngagedReflectsProbeMode() {
        var collector = SessionStatsCollector()
        for _ in 0..<8 {
            collector.recordProbeOutcome(answered: false, pongSeenWithinLastSecond: false)
        }
        #expect(collector.probeMode == .fallback)
        #expect(collector.snapshot(now: 0).isFallbackEngaged == true)
    }

    @Test func heartbeatRoundTripFeedsRTTStats() {
        var collector = SessionStatsCollector()
        collector.recordHeartbeatRoundTrip(t1: 0, t2: 1000, t3: 1000, t4: 2000)
        let snapshot = collector.snapshot(now: 0)
        #expect(snapshot.rttP50 == 0.002)
    }
}
