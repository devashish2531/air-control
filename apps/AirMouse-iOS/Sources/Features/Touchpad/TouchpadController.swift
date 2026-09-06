// Features/Touchpad/TouchpadController.swift
// Maps `TouchpadIntent`s (from `TouchpadUIView`, via `TouchpadIntentSink`) onto the motion and
// control-message wire effects, applying `UserSettings` (spec §4.1.9 Gestures section) along the
// way. This is the seam the mapping tests exercise directly (this agent's assignment: "controller
// mapping from intents to sink calls under different settings").
//
// spec §4.2.4: "The client sends raw finger deltas in points ... gain and acceleration are
// applied on the host" — so, deliberately, nothing here scales `.move`/`.scrollChanged` deltas by
// `sensitivity`/`scrollSpeed`, and nothing flips their sign for natural scroll (spec §3.6.4: "the
// host inverts the sign of both axes for natural"). Those settings only ever travel to the host
// as fields of the `Settings` message (`pushSettingsToHost()`), never as a client-side
// transformation of the datagram deltas — this is the one place this agent's assignment text
// ("sensitivity → recognizer config") is deliberately not followed literally: `GestureConfig`
// (AirMouseFilters, finished, not modified here) has no gain/sensitivity field at all, exactly
// because the spec assigns that entirely to the host.
//
// Deviation: `UserSettings.GestureSettings` (Services/DocumentStore/UserSettings.swift, owned by
// another agent, not modified here) models only `tapToClick`, `tapAndDrag`, `dragLock`,
// `naturalScroll`, `momentum`, `scrollSpeed` — several spec §4.1.9 Gestures rows have no backing
// field yet (palm rejection on/off, axis lock on/off, pinch mode, three-finger mode, double-click
// interval, tap duration, long-press right-click + duration, show click buttons/modifier strip).
// `gestureConfig` falls back to `GestureConfig()`'s spec-default values for all of those.
//
// Deviation: `TouchpadIntent.swipe`/`.pinch`/`.fourFingerTap` need a wire `key` message (spec
// §4.2.5) that `ControlMessageSink` (deliberately minimal per this agent's assignment) has no
// method for; they are recognized and logged but not currently sent to the host.

import Foundation
import Observation
import QuartzCore
import AirMouseFilters
import AirMouseProtocol

@MainActor
@Observable
public final class TouchpadController: TouchpadIntentSink {
    /// Drives the "Dragging" mode-ribbon indicator (spec §4.1.4).
    public private(set) var isDragLockEngaged = false

    /// On-screen click button strip visibility (spec §4.1.4 "optional"). Not persisted —
    /// `UserSettings.GestureSettings` has no `showClickButtons` field (see this file's deviation
    /// note) — so this is a per-session, in-memory toggle the screen can wire to a control.
    public var showClickButtons = true

    #if DEBUG
    /// DEBUG-only counters for `TouchpadDebugMotionLabel` (Features/Touchpad): isolates which
    /// stage of touch → `TouchpadIntent` → `MotionEnqueuing` is (or isn't) receiving data,
    /// independent of `MotionPublisher.stats` — if `debugIntentCount` never increases while
    /// dragging the pad, `TouchpadUIView`/`GestureRecognizer` never produced an intent in the
    /// first place; if it increases but `debugMoveIntentCount` doesn't, drags are being
    /// recognized as something other than `.move` (e.g. rejected as a tap/palm/edge touch).
    public private(set) var debugIntentCount = 0
    public private(set) var debugMoveIntentCount = 0
    #endif

    private let userSettings: UserSettings
    private let motion: any MotionEnqueuing
    private let controlSink: any ControlMessageSink
    private let haptics: any HapticsService

    public init(
        userSettings: UserSettings,
        motion: any MotionEnqueuing,
        controlSink: any ControlMessageSink,
        haptics: any HapticsService
    ) {
        self.userSettings = userSettings
        self.motion = motion
        self.controlSink = controlSink
        self.haptics = haptics
    }

    // MARK: Settings → gesture engine config (spec §4.1.9)

    /// Config for `TouchpadUIView.config` / `TouchpadView.config`, rebuilt from the current
    /// settings snapshot. The view re-reads this on every `updateUIView`, so no change
    /// notification plumbing is needed beyond `UserSettings` already being `@Observable`.
    public var gestureConfig: GestureConfig {
        var config = GestureConfig()
        let gestures = userSettings.snapshot.gestures
        config.tapAndDragEnabled = gestures.tapAndDrag
        config.dragLockTimeout = gestures.dragLock ? config.dragLockTimeout : nil
        config.momentumEnabled = gestures.momentum
        return config
    }

    /// The `Settings` message reflecting the current snapshot (spec §3.4.5: "on connect and on
    /// any change; full snapshot").
    public var currentSettingsMessage: Settings {
        let pointer = userSettings.snapshot.pointer
        let gestures = userSettings.snapshot.gestures
        return Settings(
            sensitivity: pointer.sensitivity,
            acceleration: Self.wireAcceleration(for: pointer.acceleration),
            scrollSpeed: gestures.scrollSpeed,
            scrollDirection: Self.wireScrollDirection(for: gestures.naturalScroll),
            momentum: gestures.momentum,
            doubleClickIntervalMs: ProtocolConstants.doubleClickIntervalMsDefault,
            pinchMode: .keys,
            textRateCharsPerSec: ProtocolConstants.textRateCharsPerSecDefault
        )
    }

    /// Sends the current settings snapshot to the host (call on appear and whenever a relevant
    /// setting changes).
    public func pushSettingsToHost() {
        controlSink.sendSettings(currentSettingsMessage)
    }

    private static func wireAcceleration(for setting: PointerAcceleration) -> Acceleration {
        switch setting {
        case .off: return .off
        case .precise: return .precise
        case .standard: return .default
        case .fast: return .fast
        }
    }

    private static func wireScrollDirection(for setting: ScrollDirectionSetting) -> ScrollDirection {
        switch setting {
        case .host: return .host
        case .natural: return .natural
        case .inverted: return .inverted
        }
    }

    // MARK: TouchpadIntentSink

    /// `TouchpadIntentSink.handle(_:timestamp:predicted:)` is synchronous (UIKit's
    /// `touchesMoved`/etc. cannot `await`), but `MotionEnqueuing`'s methods are actor-isolated
    /// `async` calls — so this spawns an unstructured `Task` to hop across. `process(_:timestamp:
    /// predicted:)` below holds the actual (fully `await`-able, therefore directly testable)
    /// mapping logic; this method is the only place that wraps it in a fire-and-forget `Task`.
    public func handle(_ intents: [TouchpadIntent], timestamp: TimeInterval, predicted: Bool) {
        Task { await process(intents, timestamp: timestamp, predicted: predicted) }
    }

    /// The testable seam: awaits every motion enqueue directly rather than detaching a `Task`, so
    /// a test can call this and assert on the sink spies immediately afterwards with no need to
    /// sleep/yield for a background `Task` to run.
    func process(_ intents: [TouchpadIntent], timestamp: TimeInterval, predicted: Bool) async {
        for intent in intents {
            await process(intent, timestamp: timestamp, predicted: predicted)
        }
    }

    private func process(_ intent: TouchpadIntent, timestamp: TimeInterval, predicted: Bool) async {
        #if DEBUG
        debugIntentCount += 1
        if case .move = intent { debugMoveIntentCount += 1 }
        #endif
        switch intent {
        case .move(let delta):
            let flags: MotionFlags = predicted ? [.predicted] : []
            await motion.enqueue(dx: delta.dx, dy: delta.dy, flags: flags, source: .touch, timestamp: timestamp)

        case .click(let button, let kind, let count):
            handleClick(button: button, kind: kind, count: count)

        case .longPressHaptic:
            haptics.fire(.secondaryClick)

        case .dragLockEngaged:
            isDragLockEngaged = true
            haptics.fire(.dragLockEngage)

        case .dragLockDisengaged:
            isDragLockEngaged = false
            haptics.fire(.dragLockRelease)

        case .scrollPhaseBegan:
            await motion.enqueueScroll(dx: 0, dy: 0, flags: [.scrollBegan], source: .touch, timestamp: timestamp)
            controlSink.sendScrollPhase(ScrollPhase(phase: .began))

        case .scrollChanged(let delta):
            await motion.enqueueScroll(dx: delta.dx, dy: delta.dy, flags: [], source: .touch, timestamp: timestamp)

        case .scrollPhaseEnded(let velocity, let momentum):
            await motion.enqueueScroll(dx: 0, dy: 0, flags: [.scrollEnded], source: .touch, timestamp: timestamp)
            controlSink.sendScrollPhase(ScrollPhase(phase: .ended, vx: velocity.x, vy: velocity.y, momentum: momentum))

        case .scrollCancelled:
            controlSink.sendScrollPhase(ScrollPhase(phase: .cancel))

        case .swipe(let direction):
            Log.app.notice("TouchpadController: three-finger swipe \(String(describing: direction), privacy: .public) recognized but not sent — ControlMessageSink has no `key` method yet")

        case .pinch(let direction):
            Log.app.notice("TouchpadController: pinch \(String(describing: direction), privacy: .public) recognized but not sent — ControlMessageSink has no `key` method yet")

        case .fourFingerTap:
            Log.app.notice("TouchpadController: four-finger tap recognized but not sent — ControlMessageSink has no `key` method yet")

        case .motionEnd:
            await motion.enqueue(dx: 0, dy: 0, flags: [.motionEnd], source: .touch, timestamp: timestamp)
        }
    }

    private func handleClick(button: ClickButton, kind: ClickKind, count: Int) {
        if kind == .tap, !userSettings.snapshot.gestures.tapToClick {
            // spec-analogous macOS "Tap to click" semantics: with it off, finger taps never
            // generate a click (physical buttons / drag press-and-hold still do, via `.down`/`.up`
            // kinds, which this guard does not touch).
            return
        }

        let wireButton: MouseButton = switch button {
        case .left: .left
        case .right: .right
        case .middle: .middle
        }
        let wireAction: ClickAction = switch kind {
        case .tap: .tap
        case .down: .down
        case .up: .up
        }
        controlSink.sendClick(Click(button: wireButton, action: wireAction, count: count, modifiers: []))

        if kind == .tap {
            haptics.fire(button == .left ? .tapClick : .secondaryClick)
        }
    }

    // MARK: On-screen click button strip (spec §4.1.4, optional)

    public func clickButtonPressed(_ button: ClickButton) {
        haptics.fire(.buttonDown)
        let wireButton: MouseButton = switch button {
        case .left: .left
        case .right: .right
        case .middle: .middle
        }
        controlSink.sendClick(Click(button: wireButton, action: .down, count: 1, modifiers: []))
    }

    public func clickButtonReleased(_ button: ClickButton) {
        haptics.fire(.buttonUp)
        let wireButton: MouseButton = switch button {
        case .left: .left
        case .right: .right
        case .middle: .middle
        }
        controlSink.sendClick(Click(button: wireButton, action: .up, count: 1, modifiers: []))
    }

    // MARK: Right-edge scroll strip (owner UI request: a dedicated one-finger vertical scroll
    // region alongside the pad, distinct from `TouchpadUIView`'s own two-finger scroll gesture —
    // spec §4.2.3's finger-count state machine is unmodified). Reuses the exact same intent path
    // as the pad's `GestureRecognizer`-driven scroll (`.scrollPhaseBegan`/`.scrollChanged`/
    // `.scrollPhaseEnded` → `MotionEnqueuing.enqueueScroll` + `ControlMessageSink.sendScrollPhase`,
    // spec §4.2.5) rather than inventing a new wire path — mirrors `AirMouseViewModel.scrollChanged
    // /scrollEnded` (Features/AirMouse, another agent's file, not modified here)'s translation-
    // tracking pattern for a `DragGesture` that only reports cumulative translation, not per-frame
    // deltas.
    private var isScrollStripActive = false
    private var lastScrollStripTranslationY: Double = 0

    /// Sync entry point for `TouchpadScrollStrip`'s `DragGesture.onChanged` (SwiftUI gesture
    /// callbacks, like UIKit's `touchesMoved`, are synchronous) — mirrors `handle(_:timestamp:
    /// predicted:)`'s `Task` hop onto the awaitable seam below.
    public func scrollStripChanged(translationY: Double) {
        Task { await processScrollStripChange(translationY: translationY) }
    }

    /// Sync entry point for `TouchpadScrollStrip`'s `DragGesture.onEnded`.
    public func scrollStripEnded(velocityY: Double) {
        Task { await processScrollStripEnd(velocityY: velocityY) }
    }

    /// The testable seam (see `process(_:timestamp:predicted:)`'s doc comment for the pattern this
    /// mirrors): directly awaitable, so a test can call it and assert on the sink spies
    /// immediately afterwards.
    func processScrollStripChange(translationY: Double) async {
        if !isScrollStripActive {
            isScrollStripActive = true
            lastScrollStripTranslationY = 0
            await process([.scrollPhaseBegan], timestamp: CACurrentMediaTime(), predicted: false)
        }
        let delta = translationY - lastScrollStripTranslationY
        lastScrollStripTranslationY = translationY
        guard delta != 0 else { return }
        await process([.scrollChanged(Delta(dx: 0, dy: delta))], timestamp: CACurrentMediaTime(), predicted: false)
    }

    func processScrollStripEnd(velocityY: Double) async {
        guard isScrollStripActive else { return }
        isScrollStripActive = false
        lastScrollStripTranslationY = 0
        await process(
            [.scrollPhaseEnded(velocity: Vector2(x: 0, y: velocityY), momentum: gestureConfig.momentumEnabled)],
            timestamp: CACurrentMediaTime(),
            predicted: false
        )
    }
}
