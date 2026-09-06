// Services/KeyboardBridge/KeyboardBridge.swift
// arch §3.2 `KeyboardBridge` — owns the hidden `KeyInputHostView`'s domain logic: live-mode text/
// delete routing, the trail label (spec §4.4.2, §11.3 "Trail length / fade"), modifier latch/lock
// (`ModifierLatchState`) + Caps Lock, and hardware-passthrough state. Conforms to the shell's
// `KeyboardBridging` protocol (`App/ServiceProtocols.swift`) so a real instance can sit in
// `AppEnvironment.keyboard` once the Connection agent's sink exists (see
// `Features/Keyboard/Keyboard+Environment.swift` for how the two are wired together).
//
// `KeyboardViewModel` (Features/Keyboard/KeyboardViewModel.swift) is the SwiftUI-facing view
// model for the whole Keyboard screen (modifier bar, extended key bar, media bar, shortcuts,
// commit buffer); it owns one `KeyboardBridge` and delegates every hidden-host-view/wire concern
// to it, keeping this type — the one the architecture doc names and `ServiceProtocols` types —
// usable standalone.

import Foundation
import Observation
import AirControlProtocol

public enum KeyboardInputMode: String, Sendable, CaseIterable {
    case live
    case commit
}

@MainActor
@Observable
public final class KeyboardBridge: KeyboardBridging {
    public var mode: KeyboardInputMode = .live
    public var isSecureEntry: Bool = false {
        didSet {
            if isSecureEntry { clearTrailImmediately() }
        }
    }
    public var isPassthroughEnabled: Bool = false
    /// Whether the hidden host view should currently hold first responder (spec §4.4.1: "while
    /// the Keyboard tab is active or ⌘K was pressed").
    public var wantsFirstResponder: Bool = false

    /// `KeyboardBridging.isHardwarePassthroughActive` — true only once passthrough is both
    /// enabled by the user and actually holding first responder (drives the iPad ⌘1–⌘5 tab-switch
    /// suspension, FR-IP-005, spec §4.1.10).
    public var isHardwarePassthroughActive: Bool {
        isPassthroughEnabled && wantsFirstResponder
    }

    /// Trail label content: last 40 chars, fading after 3 s (spec §4.4.2, §11.3); empty and never
    /// populated while `isSecureEntry` is on.
    public private(set) var trailText: String = ""
    private var trailClearTask: Task<Void, Never>?

    public var modifierLatch = ModifierLatchState()
    public var isCapsLockOn: Bool = false

    public let sink: any KeyboardEventSink

    weak var hostView: KeyInputHostView?

    public init(sink: any KeyboardEventSink = NoOpKeyboardEventSink()) {
        self.sink = sink
    }

    func attach(hostView: KeyInputHostView) {
        self.hostView = hostView
    }

    // MARK: - Live mode (spec §4.4.2)

    func handleLiveInsertedText(_ text: String, resetting view: KeyInputHostView) {
        guard mode == .live else { return }
        sink.sendText(text)
        appendTrail(text)
        modifierLatch.consumeLatchesAfterKey()
        view.resetToSentinel()
    }

    func handleLiveDeleteBackward(resetting view: KeyInputHostView) {
        guard mode == .live else { return }
        let flags = currentFlags()
        sink.sendKey(virtualKey: VirtualKey.kVK_Delete, char: nil, modifiers: flags, isDown: true)
        sink.sendKey(virtualKey: VirtualKey.kVK_Delete, char: nil, modifiers: flags, isDown: false)
        appendTrail("⌫")
        modifierLatch.consumeLatchesAfterKey()
        view.resetToSentinel()
    }

    func handleHardwareKeyEvent(_ event: HardwareKeyEvent) {
        let flags = currentFlags().union(event.modifiers)
        sink.sendKey(virtualKey: event.virtualKey, char: event.charactersIgnoringModifiers, modifiers: flags, isDown: event.isDown)
        if event.isDown {
            appendTrail(event.charactersIgnoringModifiers ?? "")
            modifierLatch.consumeLatchesAfterKey()
        }
    }

    // MARK: - Extended key bar / F-row / shortcuts (KeyboardViewModel)

    /// Sends a non-printing key or shortcut chord with the bridge's live modifier state attached
    /// (spec §4.4.3/§4.4.4), consuming any latched modifier on the down edge.
    public func sendExtendedKey(virtualKey: UInt16, char: String? = nil, extraModifiers: KeyModifiers = [], isDown: Bool) {
        let flags = currentFlags().union(extraModifiers)
        sink.sendKey(virtualKey: virtualKey, char: char, modifiers: flags, isDown: isDown)
        if isDown {
            modifierLatch.consumeLatchesAfterKey()
        }
    }

    public func sendMediaKey(_ key: MediaKey) {
        sink.sendMediaKey(key)
    }

    /// Chunks on grapheme-cluster boundaries at 4 KB (spec §4.4.2 "Commit"); the wire's own
    /// 16 KB cap (spec §11.3 "Text message max") is enforced by the Connection agent's transport.
    public func sendCommitText(_ text: String) {
        for chunk in text.chunkedByGraphemeClusters(maxBytes: 4096) {
            sink.sendText(chunk)
        }
    }

    // MARK: - Modifiers

    public func tapModifier(_ key: ModifierKey, at now: ContinuousClock.Instant = ContinuousClock.now) {
        modifierLatch.tap(key, at: now)
    }

    public func toggleCapsLock() {
        isCapsLockOn.toggle()
    }

    private func currentFlags() -> KeyModifiers {
        var flags = modifierLatch.activeFlags
        if isCapsLockOn { flags.insert(.capsLock) }
        return flags
    }

    // MARK: - Trail label

    private func appendTrail(_ text: String) {
        guard !isSecureEntry, !text.isEmpty else { return }
        trailText.append(contentsOf: text)
        if trailText.count > 40 {
            trailText = String(trailText.suffix(40))
        }
        trailClearTask?.cancel()
        trailClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.trailText = ""
        }
    }

    public func clearTrailImmediately() {
        trailClearTask?.cancel()
        trailText = ""
    }
}
