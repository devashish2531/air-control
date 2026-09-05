// HeldInputLedger — minimal stand-in for the per-session held-input bookkeeping spec §5.3.11
// describes ("if any button/modifier has been held for > 60 s without any message from its session
// → release and log"). `AirMouseCore` (the module that should eventually own per-session identity —
// see `docs/04-architecture.md` §3.1) is still just a placeholder module as of this writing, so this
// tracks one host-wide "last activity" timestamp rather than one per session, matching
// `EventInjector`'s own pointer/held-input state model (spec §5.3.2: "State per host (shared by all
// sessions — last event wins)").
//
// TODO(integration): once `SessionManager` (networking agent) threads a session identifier through
// `EventInjector`'s calls, promote this to a `[SessionID: HeldInputLedger]` so the watchdog can log
// *which* session went quiet and so one session's silence can't force-release another session's held
// button. Until then this is a deliberate simplification, not the spec-complete design.
import Foundation

/// Tracks the most recent injector activity and answers "has it been idle longer than `threshold`?"
/// Pure value type — no timers, no locks — so `EventInjector` (which already owns a `Clock` for
/// deterministic tests) can drive it directly from its own actor-isolated state.
struct HeldInputLedger: Sendable, Equatable {
    /// spec §5.3.11 / §11.3 "Held-input watchdog": 60 s.
    static let watchdogThreshold: TimeInterval = 60
    /// The assignment's own "stale release" figure; not a distinct spec constant (spec only names the
    /// 60 s watchdog) — exposed so tests can exercise the release-on-idle *mechanism* deterministically
    /// on a short threshold without waiting on (or faking) a full 60 s.
    static let testStaleThreshold: TimeInterval = 2

    private(set) var lastActivityAt: TimeInterval

    init(now: TimeInterval) {
        lastActivityAt = now
    }

    mutating func noteActivity(now: TimeInterval) {
        lastActivityAt = now
    }

    func isStale(now: TimeInterval, threshold: TimeInterval) -> Bool {
        now - lastActivityAt > threshold
    }
}
