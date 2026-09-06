// Features/Keyboard/KeyboardViewModel.swift
// @MainActor @Observable view model for the Keyboard screen (spec §4.1.6, §4.4; arch §3.2's
// "Keyboard" feature module row). Owns a `KeyboardBridge` (hidden host + modifier latch/lock +
// hardware passthrough), the commit-mode buffer, media-key repeat, and the user-editable
// shortcut row (spec §4.4.5, FR-KB-008 — stored in `UserDefaults`, arch §6.2-style keys since this
// module does not own `SettingsStore`/`UserSettings`). Haptics fire per spec §4.6's table.

import Foundation
import Observation
import AirControlProtocol

@MainActor
@Observable
public final class KeyboardViewModel {
    public let bridge: KeyboardBridge
    private let haptics: any HapticsService

    public var mode: KeyboardInputMode {
        get { bridge.mode }
        set {
            bridge.mode = newValue
            if newValue == .commit {
                commitText = ""
            }
        }
    }

    public var isSecureEntry: Bool {
        get { bridge.isSecureEntry }
        set { bridge.isSecureEntry = newValue }
    }

    public var isPassthroughEnabled: Bool {
        get { bridge.isPassthroughEnabled }
        set { bridge.isPassthroughEnabled = newValue }
    }

    /// Commit-mode's visible editor buffer (spec §4.1.6: "a visible multi-line editor with Send").
    public var commitText: String = ""

    /// Commit-mode "Return sends" toggle (spec §4.1.9 Keyboard settings row), persisted locally
    /// since this module does not own `SettingsStore`/`UserSettings`.
    public var returnSends: Bool {
        didSet { UserDefaults.standard.set(returnSends, forKey: Self.returnSendsKey) }
    }

    /// fn toggle: switches the extended key bar's F-row between F-keys and media glyphs
    /// (spec §4.4.4).
    public var isFRowShowingMedia: Bool = false

    public var shortcutRow: [ShortcutChord] {
        didSet { persistShortcutRow() }
    }

    private static let returnSendsKey = "am.keyboard.returnSends"
    private static let shortcutRowKey = "am.keyboard.shortcutRow"
    private var mediaRepeatTask: Task<Void, Never>?

    public init(bridge: KeyboardBridge, haptics: any HapticsService) {
        self.bridge = bridge
        self.haptics = haptics
        self.returnSends = UserDefaults.standard.object(forKey: Self.returnSendsKey) as? Bool ?? false
        if let data = UserDefaults.standard.data(forKey: Self.shortcutRowKey),
           let decoded = try? JSONDecoder().decode([ShortcutChord].self, from: data) {
            self.shortcutRow = decoded
        } else {
            self.shortcutRow = ShortcutChord.defaultRow
        }
    }

    public convenience init(sink: any KeyboardEventSink = NoOpKeyboardEventSink(), haptics: any HapticsService) {
        self.init(bridge: KeyboardBridge(sink: sink), haptics: haptics)
    }

    private func persistShortcutRow() {
        guard let data = try? JSONEncoder().encode(shortcutRow) else { return }
        UserDefaults.standard.set(data, forKey: Self.shortcutRowKey)
    }

    // MARK: - Screen lifecycle

    public func onAppear() {
        bridge.wantsFirstResponder = true
    }

    public func onDisappear() {
        bridge.wantsFirstResponder = false
        cancelMediaRepeat()
    }

    // MARK: - Software keyboard visibility (UI fix: hide/show affordance)

    /// Whether the hidden host view currently holds first responder — i.e. whether the software
    /// keyboard is (or would be) on screen for Live mode's typing capture.
    public var isSystemKeyboardVisible: Bool { bridge.wantsFirstResponder }

    /// Resigns the hidden host view's first responder status, dismissing the software keyboard.
    /// Live-mode typing capture (`KeyInputHostView.insertText`/`deleteBackward`) simply stops
    /// receiving events until `showSystemKeyboard()` re-arms it — this does not change `mode` or
    /// any bridge/sink semantics, only whether the view is first responder.
    public func hideSystemKeyboard() {
        bridge.wantsFirstResponder = false
    }

    /// Re-arms first responder so the software keyboard reappears (Live mode only — Commit mode's
    /// visible text editor manages its own focus).
    public func showSystemKeyboard() {
        guard mode == .live else { return }
        bridge.wantsFirstResponder = true
    }

    // MARK: - Modifier row

    public func tapModifier(_ key: ModifierKey) {
        haptics.prepare(.modifierToggle)
        bridge.tapModifier(key)
        haptics.fire(.modifierToggle)
    }

    public func modifierState(_ key: ModifierKey) -> ModifierLatchState.State {
        bridge.modifierLatch.state(for: key)
    }

    public var isCapsLockOn: Bool { bridge.isCapsLockOn }

    public func tapCapsLock() {
        haptics.prepare(.modifierToggle)
        bridge.toggleCapsLock()
        haptics.fire(.modifierToggle)
    }

    public func tapFn() {
        haptics.prepare(.modifierToggle)
        bridge.tapModifier(.function)
        isFRowShowingMedia.toggle()
        haptics.fire(.modifierToggle)
    }

    // MARK: - Extended key bar

    public func pressExtendedKey(_ key: ExtendedKey, isDown: Bool) {
        haptics.prepare(isDown ? .buttonDown : .buttonUp)
        bridge.sendExtendedKey(virtualKey: key.virtualKey, isDown: isDown)
        haptics.fire(isDown ? .buttonDown : .buttonUp)
    }

    /// Non-repeating keys (Esc, Tab, Return, F-keys, Home/End/PgUp/PgDn) — a single tap sends
    /// down then up.
    public func tapExtendedKey(_ key: ExtendedKey) {
        pressExtendedKey(key, isDown: true)
        pressExtendedKey(key, isDown: false)
    }

    // MARK: - Shortcuts

    public func fireShortcut(_ chord: ShortcutChord) {
        haptics.prepare(.tapClick)
        bridge.sendExtendedKey(virtualKey: chord.virtualKey, extraModifiers: chord.modifiers, isDown: true)
        bridge.sendExtendedKey(virtualKey: chord.virtualKey, extraModifiers: chord.modifiers, isDown: false)
        haptics.fire(.tapClick)
    }

    // MARK: - Media keys

    public func tapMediaKey(_ key: MediaKey) {
        haptics.prepare(.tapClick)
        bridge.sendMediaKey(key)
        haptics.fire(.tapClick)
    }

    /// Volume/brightness hold → repeat at the media repeat interval while held (spec §4.4.5,
    /// §11.3 "Media repeat 100 ms"). `KeyboardEventSink.sendMediaKey` has no down/up distinction,
    /// so repetition is simulated client-side by re-firing at that interval.
    public func beginMediaKeyRepeat(_ key: MediaKey) {
        cancelMediaRepeat()
        haptics.prepare(.buttonDown)
        bridge.sendMediaKey(key)
        haptics.fire(.buttonDown)
        mediaRepeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                self?.bridge.sendMediaKey(key)
            }
        }
    }

    public func endMediaKeyRepeat() {
        cancelMediaRepeat()
        haptics.fire(.buttonUp)
    }

    private func cancelMediaRepeat() {
        mediaRepeatTask?.cancel()
        mediaRepeatTask = nil
    }

    // MARK: - Commit mode

    public func sendCommit() {
        guard !commitText.isEmpty else { return }
        bridge.sendCommitText(commitText)
        commitText = ""
    }

    /// Called when Return is pressed inside the commit editor; returns whether it was consumed
    /// (i.e. "Return sends" is on and the buffer was sent) so the caller can decide whether to
    /// also insert a literal newline.
    @discardableResult
    public func handleCommitReturn() -> Bool {
        guard returnSends else { return false }
        sendCommit()
        return true
    }
}
