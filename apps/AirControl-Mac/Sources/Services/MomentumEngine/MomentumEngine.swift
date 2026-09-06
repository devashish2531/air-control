// MomentumEngine — spec §3.6.3 / §5.3.4, architecture §3.3, §4.2, §5.2:
// "Momentum synthesis per §3.6.3 on a 60 Hz DispatchSourceTimer; cancelled by scrollPhase{cancel},
// any new scroll delta, session end, or pause" and "MomentumEngine (arch table) | `inject` executor |
// 60 Hz DispatchSourceTimer (leeway 1 ms) running MomentumSynthesizer; posts momentum-phase scroll
// events; cancelled by new scroll deltas, scrollPhase{cancel}, session end, pause".
//
// Deliberately posts scroll events directly through an `EventPosting` rather than calling back into
// `EventInjector` — a momentum-phase scroll `CGEvent` needs no cursor position (`CGEvent
// (scrollWheelEvent2Source:...)` posts wherever the system cursor already is; there is no
// `mouseCursorPosition` parameter, unlike the mouse-move family) and no acceleration/clamp math, so
// there is nothing `EventInjector`-specific to delegate. This keeps `MomentumEngine` constructible and
// testable on its own, per the assignment ("tests with RecordingEventPoster and a manual clock/tick"),
// while still running on the *same* `DispatchSerialQueue` as `EventInjector` (shared instance passed
// into `init`) so the two are never concurrent with each other, matching architecture §5.2's shared
// `inject` executor row.
import AirControlFilters
import CoreGraphics
import Dispatch
import Foundation

public actor MomentumEngine {
    /// spec §3.6.3: exponential decay τ.
    public static let defaultTau: TimeInterval = MomentumSynthesizer.defaultTau
    /// spec §3.6.3 / §11.3: momentum ticks at 60 Hz.
    public static let tickInterval: TimeInterval = 1.0 / 60.0
    /// spec §3.6.3: "60 Hz (DispatchSourceTimer, leeway 1 ms)".
    public static let timerLeeway: DispatchTimeInterval = .milliseconds(1)

    private let poster: any EventPosting
    private let source: CGEventSource?
    private let queue: DispatchSerialQueue
    /// Tests disable the real 60 Hz timer and drive `tick(dt:)` manually/deterministically instead
    /// (the assignment's "manual clock/tick"); production always schedules the real timer.
    private let scheduleRealTimer: Bool

    private var synthesizer: MomentumSynthesizer
    private var timerSource: DispatchSourceTimer?

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    /// - Parameters:
    ///   - poster: where synthesized momentum scroll `CGEvent`s go (production: the same
    ///     `CGEventPoster`/`EventInjector` uses; tests: a `RecordingEventPoster`).
    ///   - source: the process's single `CGEventSource` (spec §5.3.1); pass the same instance
    ///     `EventInjector` uses so every posted event comes from one source, as the spec requires.
    ///   - queue: the shared `inject` `DispatchSerialQueue` (architecture §5.2); pass
    ///     `EventInjector`'s queue in production so the two share one executor.
    ///   - tau: momentum decay constant (spec default 350 ms).
    ///   - scheduleRealTimer: `false` in tests to disable the live 60 Hz `DispatchSourceTimer` and
    ///     drive ticks manually via `tick(dt:)` instead.
    public init(
        poster: any EventPosting,
        source: CGEventSource?,
        queue: DispatchSerialQueue,
        tau: TimeInterval = MomentumEngine.defaultTau,
        scheduleRealTimer: Bool = true
    ) {
        self.poster = poster
        self.source = source
        self.queue = queue
        self.scheduleRealTimer = scheduleRealTimer
        self.synthesizer = MomentumSynthesizer(tau: tau)
    }

    public var isActive: Bool { synthesizer.active }

    /// Starts a fling (spec §3.6.3). `velocity` is the lift velocity (finger-travel pt/s, both axes);
    /// `gain` is the scalar pixel gain to apply per axis — `ScrollGain.gain`, sign already flipped for
    /// natural scroll (spec §3.6.4) by the caller.
    public func start(velocity: Vector2, gain: Double) {
        synthesizer.start(velocity: velocity, gain: gain)
        if scheduleRealTimer {
            scheduleTimerIfNeeded()
        }
    }

    /// spec §3.6.2 cancel row: "Stop momentum: post momentum `.end`; no more events." A no-op if
    /// momentum wasn't active (e.g. a plain `scrollPhase{cancel}` with no fling in flight).
    public func cancel() {
        guard synthesizer.active else { return }
        synthesizer.cancel()
        stopTimer()
        post(MomentumTick(phase: .end, delta: .zero))
    }

    /// Advances momentum by one tick of `dt` seconds (nominally `tickInterval`) and posts the
    /// resulting scroll event, if any. Production code never calls this directly — the real timer
    /// does; tests with `scheduleRealTimer: false` call it directly to drive deterministic sequences.
    @discardableResult
    public func tick(dt: TimeInterval = MomentumEngine.tickInterval) -> MomentumTick? {
        guard let tick = synthesizer.tick(dt: dt) else { return nil }
        post(tick)
        if tick.phase == .end {
            stopTimer()
        }
        return tick
    }

    // MARK: - Posting

    /// Raw `CGScrollPhase`/`CGMomentumScrollPhase` values from `CGEventTypes.h`. The imported Swift
    /// enums exist but `CGMomentumScrollPhase.continue` collides with the `continue` keyword in a way
    /// that varies by how a given SDK snapshot exposes it; posting the documented raw integers
    /// directly via `setIntegerValueField` (verified against this SDK) sidesteps that entirely.
    private static let momentumPhaseBegin: Int64 = 1
    private static let momentumPhaseContinue: Int64 = 2
    private static let momentumPhaseEnd: Int64 = 3

    private func post(_ tick: MomentumTick) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(tick.delta.dy),
            wheel2: Int32(tick.delta.dx),
            wheel3: 0
        ) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        let phaseValue: Int64
        switch tick.phase {
        case .begin: phaseValue = Self.momentumPhaseBegin
        case .continue: phaseValue = Self.momentumPhaseContinue
        case .end: phaseValue = Self.momentumPhaseEnd
        }
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: phaseValue)
        poster.post(event)
    }

    // MARK: - Timer (spec §3.6.3: 60 Hz DispatchSourceTimer, leeway 1 ms)

    private func scheduleTimerIfNeeded() {
        guard timerSource == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.tickInterval, leeway: Self.timerLeeway)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            // architecture §5.1.3: "callbacks enter the actor with `assumeIsolated`" — valid here
            // because the timer's queue *is* this actor's own executor.
            self.assumeIsolated { isolated in
                isolated.timerFired()
            }
        }
        timerSource = timer
        timer.resume()
    }

    private func timerFired() {
        _ = tick()
    }

    private func stopTimer() {
        timerSource?.cancel()
        timerSource = nil
    }
}
