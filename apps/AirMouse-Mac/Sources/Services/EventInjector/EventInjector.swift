// EventInjector — spec §5.3 (event injection module), §5.4 (acceleration); architecture §3.3, §5.2,
// §5.3. The sole owner of the Mac's synthesized pointer/keyboard state: "virtualPos, remainder,
// heldButtons, latched modifiers, repeating keys, text queue" (architecture §3.3), running on its own
// `DispatchSerialQueue(qos: .userInteractive)` custom executor so `CGEvent.post` — a synchronous ~0.5–2
// ms Mach IPC to WindowServer (spec §8.1) — never touches the main thread (architecture §3.3 "Why
// `EventInjector` is not on the main thread").
//
// State is host-wide, not per-session ("shared by all sessions — last event wins", spec §5.3.2) —
// `SessionManager` (networking agent) is expected to hold one shared `EventInjector` instance and
// route every session's click/key/scroll/motion calls into it.
import AirMouseFilters
import AirMouseProtocol
import CoreGraphics
import Dispatch
import Foundation
import os

// MARK: - Supporting types

/// A source of the Mac's current system cursor location (spec §5.3.2: "Re-sync `virtualPos` ...  at
/// the start of each motion burst", via `CGEvent(source: nil)!.location` — research §A5). Abstracted
/// behind a closure so tests can supply a fixed/controlled location instead of reading the real
/// system cursor.
public typealias PointerLocationProvider = @Sendable () -> CGPoint

/// Real-time `Clock` (`AirMouseFilters.Clock`) backed by `ProcessInfo.systemUptime`, matching the
/// `SystemClock` pattern already used on the iOS side (`GyroEngine/SystemClock.swift`) — same
/// monotonic domain, non-decreasing, no wall-clock jumps.
public struct SystemUptimeClock: Clock {
    public init() {}
    public func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}

/// Which per-category injection cap (spec §5.3.9 / §7.6) an injector call belongs to, for the
/// optional `rateLimiter` hook. `EventInjector` itself has no notion of "session", so this hook is
/// host-wide; the spec's *per-session* caps belong to `SessionManager` (networking agent), which is
/// expected to reject over-limit input before it ever reaches `EventInjector`. This hook exists so a
/// host-wide backstop / Diagnostics "rate limited" signal can still be wired in without changing
/// `EventInjector`'s call sites.
public enum InjectionCategory: Sendable, Equatable {
    case motion, click, scroll, key, media, text
}

/// Diagnostics snapshot (architecture §3.3 "publishes counters to Diagnostics via a lock-free
/// snapshot struct", §8.1). Plain integers, incremented on the inject executor, read via
/// `snapshotCounters()`.
public struct InjectorCounters: Sendable, Equatable {
    public var motionEventsPosted: Int = 0
    public var clicksPosted: Int = 0
    public var scrollEventsPosted: Int = 0
    public var keysPosted: Int = 0
    public var mediaKeysPosted: Int = 0
    public var textCharactersPosted: Int = 0
    public var droppedWhilePaused: Int = 0
    public var droppedByRateLimiter: Int = 0
}

// MARK: - EventInjector

public actor EventInjector: EventInjecting {
    // MARK: Constants (spec §11.3)

    /// "Click min down" — a tap's down→up gap (spec §5.3.3, §11.3).
    public static let clickTapGap: TimeInterval = 0.015
    /// "tap key gap" — a key tap's down→up gap (spec §5.3.6, §11.3).
    public static let keyTapGap: TimeInterval = 0.008
    /// `deleteBackward` inter-tap spacing (spec §5.3.6, §11.3).
    public static let deleteBackwardSpacing: TimeInterval = 0.002
    /// Key auto-repeat initial delay/interval ceiling; the user's System Settings values are used
    /// instead when smaller/faster (spec §5.3.6, §11.3).
    public static let keyRepeatDelayCeiling: TimeInterval = 0.400
    public static let keyRepeatIntervalCeiling: TimeInterval = 0.040
    /// Text chunk size (UTF-16 units) and default pacing rate (spec §5.3.6, §11.3; §7.6 "≤ 500
    /// chars/s injected (configurable)").
    public static let textChunkUTF16Units = 16
    public static let defaultTextRateCharsPerSecond: Double = 500
    /// Media key tap / down↔up gap (research A4 / spec §5.3.7: "tap posts both 10 ms apart").
    public static let mediaKeyTapGap: TimeInterval = 0.010
    /// Sanity clamp on click count (spec §5.3.3): a click "> 1.5 × doubleClickIntervalMs ago or at a
    /// position > 16 pt away" from the previous one of the same button resets `count` to 1.
    public static let clickCountMaxPositionDelta: Double = 16
    public static let clickCountIntervalMultiplier: Double = 1.5

    // MARK: Dependencies

    // NOTE: none of these are `private` — `EventInjector`'s methods are split across
    // `EventInjector+Motion.swift` / `+Keyboard.swift` / `+MediaKeys.swift` extensions in other files,
    // and Swift's `private` is file-scoped (invisible even to extensions of the same type in a
    // different file), so anything those files touch must be at least `internal` (the module-visible
    // default — none of this is `public`, so it stays invisible outside this app target).
    let queue: DispatchSerialQueue
    let poster: any EventPosting
    /// spec §5.3.1: "One `CGEventSource(stateID: .hidSystemState)` for the process." `CGEventSource`
    /// isn't `Sendable`, and this single instance is deliberately shared with `MomentumEngine` (passed
    /// into its `init` below), which Swift 6's region checker otherwise flags as "sending risks
    /// causing data races" once the value is merged into `self`'s isolation region. `nonisolated
    /// (unsafe)` is safe here — the one additional site beyond the kit's two documented ones (CLAUDE.md)
    /// — because of a single-owner invariant the type system can't see: `EventInjector` and
    /// `MomentumEngine` always run on the *same* `DispatchSerialQueue` (this actor's `queue`, passed
    /// into `MomentumEngine.init(queue:)` too), so the two never touch this object concurrently.
    nonisolated(unsafe) let source: CGEventSource?
    let keycodeMapper: KeycodeMapper?
    let clock: any Clock
    let pointerLocationProvider: PointerLocationProvider
    let rateLimiter: (@Sendable (InjectionCategory) -> Bool)?
    let momentumEngine: MomentumEngine

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    // MARK: Pointer state (spec §5.3.2 — "State per host (shared by all sessions — last event wins)")

    var virtualPos: CGPoint
    var remainder: Vector2 = .zero
    var heldButtons: Set<MouseButton> = []
    var lastMotionAt: TimeInterval?
    var displayClamp: DisplayClamp
    var accelerationCurve: AccelerationCurve

    // MARK: Click state (spec §5.3.3)

    struct LastClick: Sendable {
        var at: TimeInterval
        var position: CGPoint
        var count: Int
    }
    var lastClickByButton: [MouseButton: LastClick] = [:]

    // MARK: Scroll state (spec §3.6, §5.3.4)

    var scrollGain: ScrollGain
    var scrollSessionOpen = false
    var scrollRemainder: Vector2 = .zero

    // MARK: Keyboard / modifiers (spec §5.3.6)

    var latchedModifiers: KeyModifiers = []
    var repeatingKeys: [UInt16: DispatchSourceTimer] = [:]
    var textQueueTail: Task<Void, Never>?
    var textRateCharsPerSecond: Double = EventInjector.defaultTextRateCharsPerSecond

    // MARK: Misc scheduled work (tap up-events, held-input watchdog)

    var scheduledTimers: [UUID: DispatchSourceTimer] = [:]
    var heldInputLedger: HeldInputLedger
    var watchdogTimer: DispatchSourceTimer?

    // MARK: Lifecycle / gating

    var paused = false
    var counters = InjectorCounters()

    // MARK: Init

    public init(
        poster: any EventPosting = CGEventPoster(),
        keycodeMapper: KeycodeMapper? = nil,
        clock: any Clock = SystemUptimeClock(),
        pointerLocationProvider: @escaping PointerLocationProvider = EventInjector.systemPointerLocation,
        accelerationCurve: AccelerationCurve = AccelerationCurve(),
        scrollGain: ScrollGain = ScrollGain(),
        displays: DisplayTopologySnapshot = .empty,
        rateLimiter: (@Sendable (InjectionCategory) -> Bool)? = nil,
        startHeldInputWatchdog: Bool = true,
        queueLabel: String = "com.airmouse.helper.inject"
    ) {
        let queue = DispatchSerialQueue(label: queueLabel, qos: .userInteractive)
        self.queue = queue
        self.poster = poster
        self.keycodeMapper = keycodeMapper
        self.clock = clock
        self.pointerLocationProvider = pointerLocationProvider
        self.accelerationCurve = accelerationCurve
        self.scrollGain = scrollGain
        self.rateLimiter = rateLimiter

        // spec §5.3.1: one process-wide CGEventSource, local-event suppression disabled so a burst of
        // synthesized events never makes subsequently-real local input sluggish (research A1).
        let source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        self.source = source

        self.displayClamp = DisplayClamp(displays: Self.filterRects(from: displays))
        self.virtualPos = pointerLocationProvider()
        self.heldInputLedger = HeldInputLedger(now: clock.now())
        self.momentumEngine = MomentumEngine(poster: poster, source: self.source, queue: queue)

        if startHeldInputWatchdog {
            // Can't call another actor-isolated method directly from a synchronous `init` ("actor-
            // isolated instance method ... in a synchronous nonisolated context"), and — separately —
            // once `[weak self]` is captured by an escaping closure inside `init`, "self" is copied
            // and only *nonisolated* properties may be written afterward ("cannot access property
            // 'watchdogTimer' here in nonisolated initializer"). Spawning a `Task` sidesteps both: it
            // just captures `self` for later, fully-isolated execution after `init` returns.
            Task { await self.startHeldInputWatchdog() }
        }
    }

    /// Builds and starts the held-input watchdog's poll timer (spec §5.3.11 / §11.3). Split out of
    /// `init` — see the `Task { ... }` call site's comment for why a synchronous actor initializer
    /// cannot do this work directly.
    private func startHeldInputWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // A modest poll cadence is enough for a 60 s threshold; leeway is generous since this is not
        // latency-sensitive.
        timer.schedule(deadline: .now() + 5, repeating: 5, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.assumeIsolated { isolated in
                isolated.checkHeldInputWatchdog(threshold: HeldInputLedger.watchdogThreshold)
            }
        }
        watchdogTimer = timer
        timer.resume()
    }

    /// Default `PointerLocationProvider`: the real system cursor location, readable without any
    /// permission (research A5) — used to re-sync `virtualPos` at burst start and as the injector's
    /// initial position.
    public static func systemPointerLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private static func filterRects(from snapshot: DisplayTopologySnapshot) -> [DisplayRect] {
        snapshot.displays.map { info in
            DisplayRect(frame: Rect(
                x: Double(info.bounds.minX),
                y: Double(info.bounds.minY),
                width: Double(info.bounds.width),
                height: Double(info.bounds.height)
            ))
        }
    }

    // MARK: - EventInjecting (shell protocol, `Sources/App/ServiceProtocols.swift`)

    public var isPaused: Bool {
        get async { paused }
    }

    /// spec §5.3.10: "Toggle sets `paused = true`: release-all ..., drop all input messages/datagrams."
    public func pause() async {
        guard !paused else { return }
        paused = true
        await releaseAll()
    }

    /// spec §5.3.10: "Untoggle → `hostState{paused:false}`."
    public func resume() async {
        paused = false
    }

    // MARK: - Configuration updates (HostStateObserver / Preferences, not part of the hot path)

    public func updateDisplays(_ snapshot: DisplayTopologySnapshot) {
        displayClamp = DisplayClamp(displays: Self.filterRects(from: snapshot))
    }

    public func updateAcceleration(sensitivity: Double, profile: AccelerationCurve.Profile) {
        accelerationCurve.sensitivity = sensitivity
        accelerationCurve.profile = profile
    }

    public func updateScroll(speed: Double, invertForNatural: Bool) {
        scrollGain.scrollSpeed = speed
        scrollGain.invertForNatural = invertForNatural
    }

    public func updateTextRate(charsPerSecond: Double) {
        textRateCharsPerSecond = max(1, charsPerSecond)
    }

    // MARK: - Diagnostics

    public func snapshotCounters() -> InjectorCounters {
        counters
    }

    // MARK: - Shared helpers used across files

    /// spec §5.3.2 pseudocode's `currentModifierFlags` / §5.3.6 "Flags persist onto subsequent
    /// clicks/keys/moves" — the latched modifier set, converted to `CGEventFlags`.
    func currentCGEventFlags(additional: KeyModifiers = []) -> CGEventFlags {
        cgFlags(latchedModifiers.union(additional))
    }

    func cgFlags(_ mods: KeyModifiers) -> CGEventFlags {
        var flags: CGEventFlags = []
        if mods.contains(.command) { flags.insert(.maskCommand) }
        if mods.contains(.option) { flags.insert(.maskAlternate) }
        if mods.contains(.control) { flags.insert(.maskControl) }
        if mods.contains(.shift) || mods.contains(.capsLock) { flags.insert(.maskShift) }
        if mods.contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }

    /// Wraps a post with the `udp.receive->inject.post`-style signpost interval (architecture §8:
    /// "signpost intervals for the inject path"), and bumps the rate-limiter hook.
    func postSigned(_ event: CGEvent, category: InjectionCategory) -> Bool {
        if let rateLimiter, !rateLimiter(category) {
            counters.droppedByRateLimiter += 1
            return false
        }
        let state = Signposts.beginInjectInterval()
        poster.post(event)
        Signposts.endInjectInterval(state: state)
        return true
    }

    /// Schedules `work` to run isolated to this actor after `delay` seconds, via a `DispatchSourceTimer`
    /// on this actor's own queue (never `usleep`/`Task.sleep`-based scheduling for spec-mandated gaps
    /// like the 15 ms click tap or 8 ms key tap — spec §5.3.3/§5.3.6 explicitly call out
    /// `DispatchSourceTimer`, "never `usleep`").
    func scheduleAfter(_ delay: TimeInterval, execute work: @escaping @Sendable (isolated EventInjector) -> Void) {
        let id = UUID()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.assumeIsolated { isolated in
                isolated.scheduledTimers.removeValue(forKey: id)
                work(isolated)
            }
        }
        scheduledTimers[id] = timer
        timer.resume()
    }

    /// spec §5.3.11: "a watchdog: if any button/modifier has been held for > 60 s without any message
    /// from its session → release and log." (See `HeldInputLedger`'s TODO(integration) note: this is
    /// host-wide, not per-session, until `AirMouseCore` gives us session identity.) Exposed
    /// (non-`private`) so tests can call it directly with a short `threshold` and a `ManualClock`
    /// instead of waiting on the real 5 s poll / 60 s threshold.
    func checkHeldInputWatchdog(threshold: TimeInterval) {
        let now = clock.now()
        guard !heldButtons.isEmpty || !latchedModifiers.isEmpty || !repeatingKeys.isEmpty else { return }
        guard heldInputLedger.isStale(now: now, threshold: threshold) else { return }
        Log.inject.warning("EventInjector: held-input watchdog fired (idle > \(threshold, privacy: .public)s) — releasing all")
        Task { await self.releaseAll() }
    }

    func noteActivity() {
        heldInputLedger.noteActivity(now: clock.now())
    }
}
