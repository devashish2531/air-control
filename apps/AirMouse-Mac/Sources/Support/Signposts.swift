// arch §8 — signpost intervals for the inject path. This file only provides the shared `OSSignposter`
// instance and thin wrappers; the actual `udp.receive → inject.post` interval is emitted by the
// EventInjector/MotionPipeline actors, which are owned by the injection agent (not this module).
import os

public enum Signposts {
    /// One signposter per logging category that needs interval instrumentation. Keep this list small;
    /// add a case only when a real hot path needs it.
    public static let inject = OSSignposter(logger: Log.inject)

    /// Begins the `udp.receive → inject.post` interval (arch §8, "Diagnostics HUD").
    @discardableResult
    public static func beginInjectInterval(_ name: StaticString = "udp.receive->inject.post") -> OSSignpostIntervalState {
        inject.beginInterval(name)
    }

    public static func endInjectInterval(_ name: StaticString = "udp.receive->inject.post", state: OSSignpostIntervalState) {
        inject.endInterval(name, state)
    }
}
