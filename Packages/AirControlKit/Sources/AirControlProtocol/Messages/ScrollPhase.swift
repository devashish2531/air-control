import Foundation

/// `scrollPhase` (C→H). spec §3.4.5: "`phase` enum(began|ended|cancel), `vx`, `vy` num?
/// (px/s at lift, only with `ended`), `momentum` bool? (with `ended`; false suppresses momentum).
/// Deltas themselves travel on the motion channel (§3.6)."
public struct ScrollPhase: Codable, Sendable, Equatable {
    public var phase: ScrollPhaseKind
    public var vx: Double?
    public var vy: Double?
    public var momentum: Bool?

    public init(phase: ScrollPhaseKind, vx: Double? = nil, vy: Double? = nil, momentum: Bool? = nil) {
        self.phase = phase
        self.vx = vx
        self.vy = vy
        self.momentum = momentum
    }
}
