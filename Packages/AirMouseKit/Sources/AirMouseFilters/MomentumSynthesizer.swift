import Foundation

/// Momentum-scroll event phase (mirrors `scrollWheelEventMomentumPhase`, spec §3.6.3/§5.3.4).
public enum MomentumPhase: Sendable, Equatable {
    case begin
    case `continue`
    case end
}

/// One synthesized momentum tick.
public struct MomentumTick: Sendable, Equatable {
    public let phase: MomentumPhase
    /// Whole-pixel delta for this tick; sub-pixel remainder is carried internally between ticks.
    public let delta: Delta

    public init(phase: MomentumPhase, delta: Delta) {
        self.phase = phase
        self.delta = delta
    }
}

/// Exponential-decay scroll momentum (spec §3.6.3): "at 60 Hz ... `v ← v · exp(−Δt/τ)`, τ = 350 ms;
/// delta = v · Δt · scrollGain, accumulated with sub-pixel remainders; first tick posts momentum
/// `.begin`, then `.continue`, stop when |v| < 0.5 px/frame → `.end`."
///
/// Deterministic given the sequence of `tick(dt:)` calls — no wall-clock reads. `start(velocity:gain:)`
/// takes the fling velocity (finger-travel points/s, "mean of last 3 frames" per spec §4.2.5) and the
/// scalar pixel gain to apply per axis (already including the natural-scroll sign, spec §3.6.3/§5.3.4).
public struct MomentumSynthesizer: Sendable {
    public static let defaultTau: TimeInterval = 0.350
    /// Stop threshold, px/frame (spec §3.6.3 / §11.3).
    public static let stopThreshold: Double = 0.5
    /// Minimum lift speed for a fling to start momentum at all (spec §3.6.2/§11.3 `flingMinVelocity`).
    public static let minFlingVelocity: Double = 300

    public var tau: TimeInterval

    private var velocity: Vector2 = .zero      // pt/s, finger-travel units, decaying
    private var axisGain: Vector2 = Vector2(x: 1, y: 1)
    private var remainder: Vector2 = .zero
    public private(set) var isActive: Bool = false
    private var hasEmittedBegin: Bool = false

    public init(tau: TimeInterval = MomentumSynthesizer.defaultTau) {
        self.tau = tau
    }

    public var active: Bool { isActive }

    /// Starts a fling. `velocity` is the lift velocity in points/s; `gain` is the scalar scroll gain
    /// (spec `scrollGain(scrollSpeed)`, sign already applied for natural scroll) applied to both axes.
    public mutating func start(velocity: Vector2, gain: Double) {
        self.velocity = velocity
        self.axisGain = Vector2(x: gain, y: gain)
        self.remainder = .zero
        self.isActive = true
        self.hasEmittedBegin = false
    }

    /// spec: cancelled by `scrollPhase{cancel}`, a new motion datagram with non-zero scroll, session
    /// end, or pause. Does not itself emit a `.end` tick — the caller decides whether one is needed.
    public mutating func cancel() {
        isActive = false
        hasEmittedBegin = false
        velocity = .zero
        remainder = .zero
    }

    /// Advances by one tick of `dt` seconds (nominally 1/60 s) and returns the event to post, or
    /// `nil` if inactive.
    public mutating func tick(dt: TimeInterval) -> MomentumTick? {
        guard isActive else { return nil }

        velocity = velocity * exp(-dt / tau)

        let rawDx = velocity.x * dt * axisGain.x + remainder.x
        let rawDy = velocity.y * dt * axisGain.y + remainder.y
        let ix = rawDx.rounded(.towardZero)
        let iy = rawDy.rounded(.towardZero)
        remainder = Vector2(x: rawDx - ix, y: rawDy - iy)

        // Stop decision is based on the continuous (pre-truncation) per-tick magnitude so it is
        // independent of where sub-pixel remainder happens to land.
        let framePixels = Vector2(x: velocity.x * axisGain.x, y: velocity.y * axisGain.y).length * dt

        let phase: MomentumPhase
        if !hasEmittedBegin {
            phase = .begin
            hasEmittedBegin = true
        } else if framePixels < MomentumSynthesizer.stopThreshold {
            phase = .end
            isActive = false
        } else {
            phase = .continue
        }
        return MomentumTick(phase: phase, delta: Delta(dx: ix, dy: iy))
    }
}
