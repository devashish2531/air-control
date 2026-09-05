import Testing
@testable import AirMouseCore

@Suite struct RateLimiterTests {
    @Test func tokenBucketAllowsBurstThenBlocks() {
        var bucket = TokenBucket(ratePerSecond: 200, burst: 400, now: 0)
        for _ in 0..<400 {
            #expect(bucket.tryConsume(now: 0) == true)
        }
        #expect(bucket.tryConsume(now: 0) == false)
    }

    @Test func tokenBucketRefillsOverTime() {
        var bucket = TokenBucket(ratePerSecond: 200, burst: 400, now: 0)
        for _ in 0..<400 {
            bucket.tryConsume(now: 0)
        }
        #expect(bucket.tryConsume(now: 0) == false)
        // After 0.01s, 2 tokens should have refilled (200/s * 0.01s = 2).
        #expect(bucket.tryConsume(now: 0.01) == true)
        #expect(bucket.tryConsume(now: 0.01) == true)
        #expect(bucket.tryConsume(now: 0.01) == false)
    }

    @Test func tokenBucketNeverExceedsBurstCapacity() {
        var bucket = TokenBucket(ratePerSecond: 200, burst: 400, now: 0)
        #expect(bucket.availableTokens(now: 1000) == 400)
    }

    @Test func controlMessageRateLimitPerSession() {
        var limiter = RateLimiter()
        var allowedCount = 0
        for _ in 0..<401 {
            if limiter.allowControlMessage(sessionKey: "s1", now: 0) {
                allowedCount += 1
            }
        }
        #expect(allowedCount == 400)
    }

    @Test func controlMessageRateLimitIsPerSessionIndependent() {
        var limiter = RateLimiter()
        for _ in 0..<400 {
            #expect(limiter.allowControlMessage(sessionKey: "s1", now: 0) == true)
        }
        #expect(limiter.allowControlMessage(sessionKey: "s1", now: 0) == false)
        // A different session key gets its own bucket.
        #expect(limiter.allowControlMessage(sessionKey: "s2", now: 0) == true)
    }

    @Test func handshakeRateLimitFiveExcessPerMinutePerIP() {
        var limiter = RateLimiter()
        for _ in 0..<5 {
            #expect(limiter.allowHandshakeAttempt(sourceIP: "1.2.3.4", now: 0) == true)
        }
        #expect(limiter.allowHandshakeAttempt(sourceIP: "1.2.3.4", now: 0) == false)
    }

    @Test func handshakeRateLimitIsPerIPIndependent() {
        var limiter = RateLimiter()
        for _ in 0..<5 {
            limiter.allowHandshakeAttempt(sourceIP: "1.2.3.4", now: 0)
        }
        #expect(limiter.allowHandshakeAttempt(sourceIP: "1.2.3.4", now: 0) == false)
        #expect(limiter.allowHandshakeAttempt(sourceIP: "5.6.7.8", now: 0) == true)
    }

    @Test func removingSessionDropsItsBucket() {
        var limiter = RateLimiter()
        for _ in 0..<400 {
            limiter.allowControlMessage(sessionKey: "s1", now: 0)
        }
        #expect(limiter.allowControlMessage(sessionKey: "s1", now: 0) == false)
        limiter.removeSession(sessionKey: "s1")
        // A fresh bucket for the same key starts full again.
        #expect(limiter.allowControlMessage(sessionKey: "s1", now: 0) == true)
    }
}
