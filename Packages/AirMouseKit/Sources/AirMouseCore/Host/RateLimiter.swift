import Foundation
import AirMouseProtocol

/// A token bucket (spec §7.6, §11.3): "Control messages | ≤ 200/s per session (burst 400)".
/// Pure value type driven by an explicit `now` on every call (arch §3.1: no timers in the kit).
public struct TokenBucket: Sendable, Equatable {
    public let ratePerSecond: Double
    public let burst: Double
    private var tokens: Double
    private var lastRefill: TimeInterval

    public init(ratePerSecond: Double, burst: Double, now: TimeInterval = 0) {
        self.ratePerSecond = ratePerSecond
        self.burst = burst
        self.tokens = burst
        self.lastRefill = now
    }

    /// Refills based on elapsed time, then attempts to withdraw one token.
    ///
    /// - Returns: `true` if a token was available (request allowed), `false` if the bucket was
    ///   empty (request should be counted against the excess-closes-session rule, spec §3.0).
    @discardableResult
    public mutating func tryConsume(now: TimeInterval, cost: Double = 1) -> Bool {
        let elapsed = max(0, now - lastRefill)
        tokens = min(burst, tokens + elapsed * ratePerSecond)
        lastRefill = now
        guard tokens >= cost else { return false }
        tokens -= cost
        return true
    }

    public func availableTokens(now: TimeInterval) -> Double {
        min(burst, tokens + max(0, now - lastRefill) * ratePerSecond)
    }
}

/// Per-session, per-message-class rate limiting (spec §7.6): control messages (200/s, burst 400)
/// and the handshake-attempts-per-IP limiter (5/min, excess closed pre-TLS for 60 s) — modeled
/// together here since both are "token bucket per key" instances of the same primitive.
public struct RateLimiter: Sendable {
    private var controlBuckets: [String: TokenBucket] = [:]
    private var handshakeBuckets: [String: TokenBucket] = [:]

    public init() {}

    /// spec §3.0 / §11.3: control messages ≤ 200/s per session, burst 400.
    public mutating func allowControlMessage(sessionKey: String, now: TimeInterval) -> Bool {
        var bucket = controlBuckets[sessionKey] ?? TokenBucket(
            ratePerSecond: Double(ProtocolConstants.controlMessageRatePerSecond),
            burst: Double(ProtocolConstants.controlMessageBurst),
            now: now
        )
        let allowed = bucket.tryConsume(now: now)
        controlBuckets[sessionKey] = bucket
        return allowed
    }

    /// spec §3.2.1 / §7.6 / §11.3: handshake attempts ≤ 5/min per source IP.
    public mutating func allowHandshakeAttempt(sourceIP: String, now: TimeInterval) -> Bool {
        var bucket = handshakeBuckets[sourceIP] ?? TokenBucket(
            ratePerSecond: Double(ProtocolConstants.pairingRateLimitPerMinutePerIP) / 60.0,
            burst: Double(ProtocolConstants.pairingRateLimitPerMinutePerIP),
            now: now
        )
        let allowed = bucket.tryConsume(now: now)
        handshakeBuckets[sourceIP] = bucket
        return allowed
    }

    /// Drops a session's bucket (on close, to bound memory).
    public mutating func removeSession(sessionKey: String) {
        controlBuckets.removeValue(forKey: sessionKey)
    }
}
