import Testing
@testable import AirMouseCore

@Suite struct BackoffTests {
    @Test func stepSequenceMatchesSpec() {
        #expect(Backoff.baseDelay(attemptIndex: 0) == 0.25)
        #expect(Backoff.baseDelay(attemptIndex: 1) == 0.5)
        #expect(Backoff.baseDelay(attemptIndex: 2) == 1.0)
        #expect(Backoff.baseDelay(attemptIndex: 3) == 2.0)
        #expect(Backoff.baseDelay(attemptIndex: 4) == 4.0)
    }

    @Test func stepCapsAtFourSecondsBeyondTable() {
        #expect(Backoff.baseDelay(attemptIndex: 5) == 4.0)
        #expect(Backoff.baseDelay(attemptIndex: 100) == 4.0)
    }

    @Test func mutatingSequenceAdvancesThroughSteps() {
        var backoff = Backoff()
        #expect(backoff.nextDelay() == 0.25)
        #expect(backoff.nextDelay() == 0.5)
        #expect(backoff.nextDelay() == 1.0)
        #expect(backoff.nextDelay() == 2.0)
        #expect(backoff.nextDelay() == 4.0)
        #expect(backoff.nextDelay() == 4.0)
    }

    @Test func resetReturnsToFirstStep() {
        var backoff = Backoff()
        _ = backoff.nextDelay()
        _ = backoff.nextDelay()
        backoff.reset()
        #expect(backoff.nextDelay() == 0.25)
    }

    @Test func jitterStaysWithinPlusMinus20Percent() {
        let base = Backoff.baseDelay(attemptIndex: 2) // 1.0
        let high = Backoff.jitteredDelay(attemptIndex: 2, unitJitter: 1)
        let low = Backoff.jitteredDelay(attemptIndex: 2, unitJitter: -1)
        #expect(abs(high - base * 1.2) < 0.0001)
        #expect(abs(low - base * 0.8) < 0.0001)
    }

    @Test func jitterClampsOutOfRangeInput() {
        let base = Backoff.baseDelay(attemptIndex: 0)
        #expect(Backoff.jitteredDelay(attemptIndex: 0, unitJitter: 5) == Backoff.jitteredDelay(attemptIndex: 0, unitJitter: 1))
        #expect(Backoff.jitteredDelay(attemptIndex: 0, unitJitter: -5) == Backoff.jitteredDelay(attemptIndex: 0, unitJitter: -1))
        #expect(Backoff.jitteredDelay(attemptIndex: 0, unitJitter: 0) == base)
    }

    @Test func hasGivenUpAtTenMinutes() {
        #expect(Backoff.hasGivenUp(elapsedSinceReconnectingBegan: 599) == false)
        #expect(Backoff.hasGivenUp(elapsedSinceReconnectingBegan: 600) == true)
        #expect(Backoff.hasGivenUp(elapsedSinceReconnectingBegan: 1200) == true)
    }
}
