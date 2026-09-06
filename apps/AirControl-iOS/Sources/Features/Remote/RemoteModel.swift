// Features/Remote/RemoteModel.swift
// Presenter + Media state and button→sink mapping for spec §4.1.7. Every button ends up calling
// exactly one `RemoteCommandSink` method; this model owns none of the wire code itself (that's
// the Connection agent's job, reached only through the sink) and none of the touch/gesture code
// (that's `RemoteScreen`'s job) — it is the seam the button-mapping tests exercise directly.

import Foundation
import Observation
import AirControlProtocol

/// Presenter/Media segments (spec §4.1.7: "Segmented Presenter / Media").
public enum RemoteSegment: String, CaseIterable, Sendable, Identifiable {
    case presenter
    case media
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .presenter: String(localized: "Presenter", comment: "Remote segment title")
        case .media: String(localized: "Media", comment: "Remote segment title")
        }
    }
}

/// Presenter profile, detected from `hostState.frontmostApp` (spec §4.1.7: "active profile
/// (Keynote / PowerPoint / Generic)"). Drives which Start-presentation shortcut is sent.
public enum PresenterProfile: Sendable, Equatable {
    case keynote
    case powerPoint
    case generic

    /// Matches on the frontmost app's display name (or bundle-style identifier substring) since
    /// this module only receives `hostState.frontmostApp`'s name, not a bundle ID (spec §11.1
    /// lists `frontmostApp` as the optional field's contents; the exact substructure — name only
    /// vs. name+bundleID — is left to the Connection agent's `hostState` decoder, so this matches
    /// defensively on either).
    public static func detect(fromFrontmostAppName name: String?) -> PresenterProfile {
        guard let name else { return .generic }
        let lowered = name.lowercased()
        if lowered.contains("keynote") { return .keynote }
        if lowered.contains("powerpoint") { return .powerPoint }
        return .generic
    }

    public var title: String {
        switch self {
        case .keynote: String(localized: "Keynote", comment: "Presenter profile name")
        case .powerPoint: String(localized: "PowerPoint", comment: "Presenter profile name")
        case .generic: String(localized: "Generic", comment: "Presenter profile name")
        }
    }
}

/// A repeating "hold to keep firing" control (spec: "volume ... with a slider-like repeat on
/// long-press", same treatment applied to brightness). Not a real analog slider — see this
/// agent's final-report deviation note: the wire has no continuous `volume` level control wired
/// through this sink (the given `RemoteCommandSink` contract has no absolute-level method), so
/// volume/brightness are modeled as repeatable taps of the corresponding `MediaKey`, matching how
/// a physical keyboard's volume/brightness keys behave when held.
@MainActor
final class RepeatingMediaKeyController {
    private var timer: Timer?
    // Stored (rather than captured directly by the `Timer` blocks below) so those blocks — which
    // `Timer`'s API types as `@Sendable` — only need to capture `self` weakly, not a non-Sendable
    // `() -> Void` value.
    private var action: (() -> Void)?
    private let initialDelay: TimeInterval
    private let repeatInterval: TimeInterval

    init(initialDelay: TimeInterval = 0.35, repeatInterval: TimeInterval = 0.12) {
        self.initialDelay = initialDelay
        self.repeatInterval = repeatInterval
    }

    /// Fires `action` once immediately, then again after `initialDelay`, then every
    /// `repeatInterval` until `stop()`.
    func start(action: @escaping () -> Void) {
        stop()
        self.action = action
        action()
        timer = Timer.scheduledTimer(withTimeInterval: initialDelay, repeats: false) { [weak self] _ in
            // `Timer.scheduledTimer` fires on the run loop it was scheduled from, which is the
            // main run loop here since `start()` only ever runs on the main actor.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.action?()
                self.timer = Timer.scheduledTimer(withTimeInterval: self.repeatInterval, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.action?()
                    }
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        action = nil
    }
}

/// Presenter countdown/stopwatch timer card (spec §4.1.7: "Timer card: stopwatch with
/// Start/Pause/Reset, optional countdown picker; haptic at 5:00 and 1:00 remaining").
@MainActor
@Observable
public final class PresenterTimerModel {
    public enum Mode: Sendable, Equatable {
        case stopwatch
        case countdown(totalSeconds: Int)
    }

    public private(set) var isRunning = false
    public private(set) var elapsedSeconds: Int = 0
    public var mode: Mode = .stopwatch

    /// Fired once per crossing of the 5:00/1:00-remaining thresholds (countdown mode only), so the
    /// caller can trigger `HapticEvent.countdownWarning` (spec §4.6) exactly once per threshold.
    public var onCountdownWarning: (() -> Void)?

    private var timer: Timer?
    private var warnedFiveMinutes = false
    private var warnedOneMinute = false

    public init() {}

    public var remainingSeconds: Int? {
        guard case .countdown(let total) = mode else { return nil }
        return max(0, total - elapsedSeconds)
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // `Timer.scheduledTimer` fires on the run loop it was scheduled from, which is the
            // main run loop here since `start()` only ever runs on the main actor.
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    public func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    public func reset() {
        pause()
        elapsedSeconds = 0
        warnedFiveMinutes = false
        warnedOneMinute = false
    }

    private func tick() {
        elapsedSeconds += 1
        guard let remaining = remainingSeconds else { return }
        if remaining <= 300, !warnedFiveMinutes {
            warnedFiveMinutes = true
            onCountdownWarning?()
        }
        if remaining <= 60, !warnedOneMinute {
            warnedOneMinute = true
            onCountdownWarning?()
        }
        if remaining <= 0 {
            pause()
        }
    }
}

/// One `showOnMediaPage` macro rendered as a launcher quick button (spec §4.1.7: "launcher row of
/// up to 8 `launchApp` macros flagged `showOnMediaPage`"). Not restricted to `.launchApp` actions
/// client-side — the Mac author decides what a media-page button does; this only enforces the
/// count and the flag, per spec.
public struct MediaLauncherButton: Sendable, Identifiable, Equatable {
    public var id: UUID { macro.id }
    public var macro: Macro
}

/// `@Observable` state for the Remote tab. Owns no networking/motion — every effect is a call
/// through `RemoteCommandSink`.
@MainActor
@Observable
public final class RemoteModel {
    public var segment: RemoteSegment = .presenter
    public let timer = PresenterTimerModel()

    /// Presenter header (spec §4.1.7: "header shows `hostState.frontmostApp.name` and the active
    /// profile").
    public var frontmostAppName: String? { sink.frontmostAppName }
    public var presenterProfile: PresenterProfile { .detect(fromFrontmostAppName: frontmostAppName) }

    /// `true` while the frontmost app looks like a browser, selecting J/L over ←/→ for seek (spec
    /// §4.1.7: "J / L when frontmost app is a browser").
    public var isBrowserFrontmost: Bool {
        guard let name = frontmostAppName?.lowercased() else { return false }
        return ["safari", "chrome", "firefox", "edge", "arc"].contains { name.contains($0) }
    }

    /// Media launcher row, capped at 8 per spec §4.1.7. Fetched independently of the Macros tab's
    /// own sync (each feature owns its own state per this agent's directory boundaries); both read
    /// through the same `sink.requestMacroList()`.
    public private(set) var mediaLauncherButtons: [MediaLauncherButton] = []
    public private(set) var isLoadingLauncher = false

    /// Presenter idle-dim (spec §4.1.7: "Presenter dims the UI to 20% after 10 s idle
    /// (configurable)"). `RemoteScreen` calls `recordActivity()` on every touch; this only tracks
    /// the derived `isDimmed` bit, not any view-layer opacity.
    public private(set) var isDimmed = false
    private var idleDimTask: Task<Void, Never>?
    private let idleDimSecondsProvider: () -> Int

    /// Switches the pointer-spotlight toggle stub (spec AM-PR-06 / this agent's assignment:
    /// "optional laser-pointer toggle stub that switches to the Touchpad tab"). `RootTabView.swift`
    /// (owned by another agent, not touched here) does not yet observe this notification — see
    /// this agent's final report for the integration note. Posting it here keeps the stub
    /// self-contained to this module per CLAUDE.md's directory-ownership rule.
    public static let switchToTouchpadNotification = Notification.Name("com.aircontrol.remote.switchToTouchpad")

    private let sink: any RemoteCommandSink
    private let haptics: (any HapticsService)?
    private let volumeController = RepeatingMediaKeyController()
    private let brightnessController = RepeatingMediaKeyController()

    public init(
        sink: any RemoteCommandSink,
        haptics: (any HapticsService)? = nil,
        idleDimSecondsProvider: @escaping () -> Int = { 10 }
    ) {
        self.sink = sink
        self.haptics = haptics
        self.idleDimSecondsProvider = idleDimSecondsProvider
        timer.onCountdownWarning = { [weak self] in
            self?.haptics?.fire(.countdownWarning)
        }
    }

    // MARK: - Presenter

    public func previousSlide() {
        sink.sendShortcut(virtualKey: VirtualKey.kVK_LeftArrow, modifiers: [])
    }

    public func nextSlide() {
        sink.sendShortcut(virtualKey: VirtualKey.kVK_RightArrow, modifiers: [])
    }

    public func blankScreen() {
        sink.sendShortcut(virtualKey: VirtualKey.kVK_ANSI_B, modifiers: [])
    }

    /// Start-from-current shortcut, profile-dependent (spec §4.1.7: "⌥⌘P Keynote, ⇧⌘Return
    /// PowerPoint, generic F5").
    public func startPresentation() {
        switch presenterProfile {
        case .keynote:
            sink.sendShortcut(virtualKey: VirtualKey.kVK_ANSI_P, modifiers: [.option, .command])
        case .powerPoint:
            sink.sendShortcut(virtualKey: VirtualKey.kVK_Return, modifiers: [.shift, .command])
        case .generic:
            sink.sendShortcut(virtualKey: VirtualKey.kVK_F5, modifiers: [])
        }
    }

    public func exitPresentation() {
        sink.sendShortcut(virtualKey: VirtualKey.kVK_Escape, modifiers: [])
    }

    /// Lock Screen (spec §4.1.7 System row / macOS standard shortcut ⌃⌘Q). "Sleep Display" is
    /// intentionally not offered — see this agent's final-report deviation note (no Eject/Power
    /// key exists in the shared `MediaKey`/`VirtualKey` vocabulary to express it).
    public func lockScreen() {
        sink.sendShortcut(virtualKey: VirtualKey.kVK_ANSI_Q, modifiers: [.control, .command])
    }

    /// Pointer-spotlight toggle stub (see `switchToTouchpadNotification`'s doc comment).
    public func togglePointerSpotlight() {
        NotificationCenter.default.post(name: Self.switchToTouchpadNotification, object: nil)
    }

    // MARK: - Media transport

    public func mediaPlayPause() { sink.sendMediaKey(.playPause) }
    public func mediaPrevious() { sink.sendMediaKey(.previous) }
    public func mediaNext() { sink.sendMediaKey(.next) }

    /// Seek ±10 s (spec §4.1.7: "← / → generic; J / L when frontmost app is a browser").
    public func seekBackward() {
        if isBrowserFrontmost {
            sink.sendShortcut(virtualKey: VirtualKey.kVK_ANSI_J, modifiers: [])
        } else {
            sink.sendShortcut(virtualKey: VirtualKey.kVK_LeftArrow, modifiers: [])
        }
    }

    public func seekForward() {
        if isBrowserFrontmost {
            sink.sendShortcut(virtualKey: VirtualKey.kVK_ANSI_L, modifiers: [])
        } else {
            sink.sendShortcut(virtualKey: VirtualKey.kVK_RightArrow, modifiers: [])
        }
    }

    public func mute() { sink.sendMediaKey(.mute) }

    public func startVolumeUp() { volumeController.start { [sink] in sink.sendMediaKey(.volumeUp) } }
    public func startVolumeDown() { volumeController.start { [sink] in sink.sendMediaKey(.volumeDown) } }
    public func stopVolumeRepeat() { volumeController.stop() }

    public func startBrightnessUp() { brightnessController.start { [sink] in sink.sendMediaKey(.brightnessUp) } }
    public func startBrightnessDown() { brightnessController.start { [sink] in sink.sendMediaKey(.brightnessDown) } }
    public func stopBrightnessRepeat() { brightnessController.stop() }

    // MARK: - Media launcher row

    /// Invokes a media-launcher-row macro (never a script kind — see `RemoteScreen`'s call site
    /// guard). Fires a success/failure haptic (spec §4.6 "Macro fired / result") but does not
    /// surface a toast; the Macros tab is the feature that owns invocation UX end-to-end.
    public func invokeLauncherMacro(_ macro: Macro) async {
        do {
            let outcome = try await sink.invokeMacro(id: macro.id, confirmed: false)
            haptics?.fire(outcome.code == .ok ? .macroSuccess : .macroFailure)
        } catch {
            haptics?.fire(.macroFailure)
            Log.app.error("RemoteModel launcher macro invoke failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func loadMediaLauncherButtons() async {
        isLoadingLauncher = true
        defer { isLoadingLauncher = false }
        do {
            let macros = try await sink.requestMacroList()
            mediaLauncherButtons = macros
                .filter(\.showOnMediaPage)
                .sorted { ($0.page, $0.order) < ($1.page, $1.order) }
                .prefix(8)
                .map(MediaLauncherButton.init)
        } catch {
            Log.app.error("RemoteModel failed to load media launcher macros: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Idle dim

    public func recordActivity() {
        isDimmed = false
        idleDimTask?.cancel()
        let seconds = idleDimSecondsProvider()
        idleDimTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.isDimmed = true
        }
    }

    public func stopIdleDimTracking() {
        idleDimTask?.cancel()
        idleDimTask = nil
        isDimmed = false
    }
}
