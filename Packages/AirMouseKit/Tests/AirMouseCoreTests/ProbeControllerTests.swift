import Testing
@testable import AirMouseCore

@Suite struct ProbeControllerTests {
    @Test func startsInNormalMode() {
        let controller = ProbeController()
        #expect(controller.mode == .normal)
        #expect(controller.probeInterval == 0.25)
    }

    @Test func firstEightProbesAllUnansweredEntersFallback() {
        var controller = ProbeController()
        for _ in 0..<7 {
            #expect(controller.recordProbeOutcome(answered: false, pongSeenWithinLastSecond: true) == .normal)
        }
        // 8th unanswered probe, all 8 unanswered -> fallback, independent of pong health.
        #expect(controller.recordProbeOutcome(answered: false, pongSeenWithinLastSecond: false) == .fallback)
    }

    @Test func firstEightProbesWithOneAnsweredDoesNotTriggerBurstRule() {
        var controller = ProbeController()
        controller.recordProbeOutcome(answered: true, pongSeenWithinLastSecond: true)
        for _ in 0..<6 {
            controller.recordProbeOutcome(answered: false, pongSeenWithinLastSecond: true)
        }
        // 8th probe overall, but not all 8 were unanswered -> stays normal (window not yet full at 12).
        #expect(controller.recordProbeOutcome(answered: false, pongSeenWithinLastSecond: true) == .normal)
    }

    @Test func elevenOfTwelveLostWithHealthyPongEntersFallback() {
        var controller = ProbeController()
        // Answer the first probe so the initial-burst rule can't fire, then lose 11 of the next 11
        // plus one more to reach a 12-probe window with 11 losses.
        controller.recordProbeOutcome(answered: true, pongSeenWithinLastSecond: true)
        for _ in 0..<10 {
            #expect(controller.recordProbeOutcome(answered: false, pongSeenWithinLastSecond: true) == .normal)
        }
        // Window now has 11 probes (1 answered, 10 lost); one more lost probe makes 12 with 11 lost.
        #expect(controller.recordProbeOutcome(answered: false, pongSeenWithinLastSecond: true) == .fallback)
    }

    @Test func elevenOfTwelveLostWithoutHealthyPongStaysNormal() {
        var controller = ProbeController()
        controller.recordProbeOutcome(answered: true, pongSeenWithinLastSecond: true)
        for _ in 0..<10 {
            controller.recordProbeOutcome(answered: false, pongSeenWithinLastSecond: false)
        }
        // TCP not healthy (no recent pong) -> the ≥11-of-12 rule must not fire.
        #expect(controller.recordProbeOutcome(answered: false, pongSeenWithinLastSecond: false) == .normal)
    }

    @Test func tenOfTwelveLostStaysNormal() {
        var controller = ProbeController()
        controller.recordProbeOutcome(answered: true, pongSeenWithinLastSecond: true)
        controller.recordProbeOutcome(answered: true, pongSeenWithinLastSecond: true)
        for _ in 0..<9 {
            controller.recordProbeOutcome(answered: false, pongSeenWithinLastSecond: true)
        }
        // 2 answered + 9 lost = 11 so far; one more lost -> 10 of 12 lost, below the 11 threshold.
        #expect(controller.recordProbeOutcome(answered: false, pongSeenWithinLastSecond: true) == .normal)
    }

    @Test func fallbackProbeIntervalIsOneHertz() {
        var controller = ProbeController()
        for _ in 0..<8 {
            controller.recordProbeOutcome(answered: false, pongSeenWithinLastSecond: false)
        }
        #expect(controller.mode == .fallback)
        #expect(controller.probeInterval == 1.0)
    }

    @Test func fiveConsecutiveAnsweredRecoversFromFallback() {
        var controller = ProbeController()
        for _ in 0..<8 {
            controller.recordProbeOutcome(answered: false, pongSeenWithinLastSecond: false)
        }
        #expect(controller.mode == .fallback)
        for _ in 0..<4 {
            #expect(controller.recordProbeOutcome(answered: true, pongSeenWithinLastSecond: true) == .fallback)
        }
        #expect(controller.recordProbeOutcome(answered: true, pongSeenWithinLastSecond: true) == .normal)
    }

    @Test func recoveryRequiresConsecutiveAnswers() {
        var controller = ProbeController()
        for _ in 0..<8 {
            controller.recordProbeOutcome(answered: false, pongSeenWithinLastSecond: false)
        }
        controller.recordProbeOutcome(answered: true, pongSeenWithinLastSecond: true)
        controller.recordProbeOutcome(answered: true, pongSeenWithinLastSecond: true)
        controller.recordProbeOutcome(answered: false, pongSeenWithinLastSecond: true) // resets the streak
        controller.recordProbeOutcome(answered: true, pongSeenWithinLastSecond: true)
        controller.recordProbeOutcome(answered: true, pongSeenWithinLastSecond: true)
        controller.recordProbeOutcome(answered: true, pongSeenWithinLastSecond: true)
        controller.recordProbeOutcome(answered: true, pongSeenWithinLastSecond: true)
        #expect(controller.mode == .fallback) // only 4 consecutive answers since the reset
        #expect(controller.recordProbeOutcome(answered: true, pongSeenWithinLastSecond: true) == .normal) // 5th
    }

    @Test func resetReturnsToInitialState() {
        var controller = ProbeController()
        for _ in 0..<8 {
            controller.recordProbeOutcome(answered: false, pongSeenWithinLastSecond: false)
        }
        #expect(controller.mode == .fallback)
        controller.reset()
        #expect(controller.mode == .normal)
        #expect(controller.probeInterval == 0.25)
    }
}
