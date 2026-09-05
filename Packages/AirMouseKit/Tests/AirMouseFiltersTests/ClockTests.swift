import Testing
@testable import AirMouseFilters

@Suite struct ClockTests {
    @Test func manualClockStartsAtGivenTime() {
        let clock = ManualClock(start: 5)
        #expect(clock.now() == 5)
    }

    @Test func manualClockAdvances() {
        let clock = ManualClock(start: 0)
        clock.advance(by: 1.5)
        #expect(clock.now() == 1.5)
        clock.advance(by: 0.5)
        #expect(clock.now() == 2.0)
    }

    @Test func manualClockCanBeSetAbsolutely() {
        let clock = ManualClock(start: 0)
        clock.set(42)
        #expect(clock.now() == 42)
    }
}

@Suite struct TimestampMicrosTests {
    @Test func encodeRoundTripsWithinOneWrap() {
        let seconds = 12.345
        let micros = TimestampMicros.encode(seconds)
        #expect(abs(TimestampMicros.seconds(micros) - seconds) < 1e-6)
    }

    @Test func elapsedSecondsForNonWrappingIntervalIsCorrect() {
        let a = TimestampMicros.encode(1.0)
        let b = TimestampMicros.encode(1.1)
        let elapsed = TimestampMicros.elapsedSeconds(from: a, to: b)
        #expect(abs(elapsed - 0.1) < 1e-6)
    }

    @Test func elapsedSecondsHandlesWraparound() {
        // Start just before the 32-bit wrap point, land just after it.
        let nearWrap = TimestampMicros.wrapPeriod - 0.005
        let a = TimestampMicros.encode(nearWrap)
        let b = TimestampMicros.encode(nearWrap + 0.010) // wraps past modulus
        let elapsed = TimestampMicros.elapsedSeconds(from: a, to: b)
        #expect(abs(elapsed - 0.010) < 1e-6)
    }

    @Test func wrapPeriodMatchesSpecProse() {
        // spec §3.5.2: "wraps every 71.6 min"
        #expect(abs(TimestampMicros.wrapPeriod / 60.0 - 71.58) < 0.05)
    }

    @Test func negativeElapsedIsRepresentedCorrectly() {
        let a = TimestampMicros.encode(5.0)
        let b = TimestampMicros.encode(4.9)
        let elapsed = TimestampMicros.elapsedSeconds(from: a, to: b)
        #expect(elapsed < 0)
        #expect(abs(elapsed + 0.1) < 1e-6)
    }
}
