// Services/KeyboardBridge/KeyInputHostView.swift
// The hidden `UITextView` host (spec §4.4.1 `KeyInputHostView`, arch §3.2 `KeyboardBridge`) that
// captures live-mode typing and hardware-keyboard passthrough while the Keyboard tab is active.
//
// Deviation from spec §4.4.2's literal algorithm: instead of diffing `textViewDidChange`'s `.text`
// against the zero-width sentinel, this subclass overrides `insertText(_:)`/`deleteBackward()`
// directly (per this agent's assignment: "captures `insertText`, `deleteBackward`") — the same
// per-keystroke information without needing string diffing, with the `markedTextRange` gate
// applied at the same point spec §4.4.2 places it ("if markedTextRange != nil → return"). The
// gating decision itself is factored into `shouldForwardTextEvent(hasMarkedText:)`, a pure
// function, so it can be unit-tested without a live `UITextInput` session (a real `UITextView`'s
// `markedTextRange` only reflects IME state while it holds an active input session, which a
// headless test target cannot reliably simulate) — see `Tests/KeyboardBridgeTests.swift`.
//
// Hardware passthrough (spec §4.4.6) similarly factors its HID-usage → `VirtualKey` / modifier
// resolution and "should this become a `key` event rather than flow through `insertText`" policy
// into `resolveHardwareKey(hidUsage:modifierFlags:charactersIgnoringModifiers:)`, a pure function
// over primitive values — `UIPress`/`UIKey` have no public initializer, so this is what makes the
// HID→kVK mapping unit-testable "through the bridge" without needing real hardware press objects.

import UIKit
import AirMouseProtocol

@MainActor
public protocol KeyInputHostViewDelegate: AnyObject {
    /// A whole, non-marked-text insertion (spec §4.4.2's "inserted string"). Never called while
    /// IME composition is in progress (`markedTextRange != nil`).
    func keyInputHost(_ view: KeyInputHostView, didInsertText text: String)
    /// A single backward deletion (spec §4.4.2's "deletion of the sentinel").
    func keyInputHostDidDeleteBackward(_ view: KeyInputHostView)
    /// A resolved hardware key press or release (spec §4.4.6).
    func keyInputHost(_ view: KeyInputHostView, hardwareKeyEvent event: HardwareKeyEvent)
    /// The view's own "Done" input accessory was tapped (UI fix: the software keyboard otherwise
    /// has no way to dismiss itself while this hidden view holds first responder). The delegate
    /// is responsible for the corresponding `KeyboardBridge.wantsFirstResponder = false`; this
    /// view only resigns its own first-responder status.
    func keyInputHostDidRequestHide(_ view: KeyInputHostView)
}

/// One resolved hardware key press or release, ready for `KeyboardEventSink.sendKey` routing
/// (spec §4.4.6): the HID usage has already been mapped to a `VirtualKey` via `HIDKeycodeTable`
/// and `UIKeyModifierFlags` to `KeyModifiers`.
public struct HardwareKeyEvent: Sendable, Equatable {
    public let virtualKey: UInt16
    public let charactersIgnoringModifiers: String?
    public let modifiers: KeyModifiers
    public let isDown: Bool

    public init(virtualKey: UInt16, charactersIgnoringModifiers: String?, modifiers: KeyModifiers, isDown: Bool) {
        self.virtualKey = virtualKey
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.modifiers = modifiers
        self.isDown = isDown
    }
}

/// Hidden 1 × 1 pt text input host. `KeyInputHostRepresentable` is the SwiftUI wrapper; this
/// class has no SwiftUI/Observation dependency so it stays a plain, directly-instantiable UIKit
/// view for tests.
public final class KeyInputHostView: UITextView {
    /// Zero-width space sentinel (spec §4.4.2) so the view never sits truly empty; kept mainly so
    /// VoiceOver/system text-input machinery always has *some* content to reason about. The
    /// per-keystroke `insertText`/`deleteBackward` overrides below are the actual source of truth
    /// (see file header), so unlike spec §4.4.2's literal diff algorithm this class never needs to
    /// inspect `.text` itself.
    public static let sentinel = "\u{200B}"

    public weak var hostDelegate: KeyInputHostViewDelegate?

    /// Tracks HID usages currently held down: a physical key held on an external keyboard
    /// re-invokes `pressesBegan` at the OS's own key-repeat rate, but spec §4.4.3/§11.3 puts
    /// repeat entirely on the host (from a single `key{down}`), so repeats of an already-held key
    /// must not be forwarded again.
    private var heldHIDUsages: Set<UInt16> = []

    public var isHardwarePassthroughEnabled: Bool = false

    /// HID usages intercepted as `key` events regardless of modifiers (nav cluster, editing keys,
    /// F-row) — everything else only becomes a `key` event when a ⌘/⌃/⌥ chord is held (spec
    /// §4.4.3: plain printable text with no ⌘/⌃/⌥ always takes the Unicode `insertText` path).
    nonisolated static let nonPrintingHIDUsages: Set<UInt16> = {
        var usages: Set<UInt16> = [0x29, 0x2B, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x50, 0x51, 0x52]
        usages.formUnion(0x3A...0x45) // F1–F12
        usages.formUnion(0x68...0x6F) // F13–F20
        return usages
    }()

    public override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configureCommon()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureCommon()
    }

    private func configureCommon() {
        text = Self.sentinel
        textContentType = nil
        keyboardType = .default
        returnKeyType = .default
        isScrollEnabled = false
        backgroundColor = .clear
        configureForLiveMode()
    }

    /// spec §4.4.1: live mode disables every text-transformation feature so behavior stays
    /// predictable and nothing autocorrect-related is ever logged.
    public func configureForLiveMode() {
        autocorrectionType = .no
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        autocapitalizationType = .none
        isSecureTextEntry = false
    }

    /// spec §4.4.1: commit mode follows the user's iOS settings.
    public func configureForCommitMode() {
        autocorrectionType = .default
        spellCheckingType = .default
        smartQuotesType = .default
        smartDashesType = .default
        smartInsertDeleteType = .default
        autocapitalizationType = .sentences
        isSecureTextEntry = false
    }

    /// Secure entry (spec §4.1.6 eye-slash toggle) forces autocorrect/prediction off regardless of
    /// mode; the view model is responsible for not persisting/logging/displaying typed content.
    public func configureForSecureEntry() {
        autocorrectionType = .no
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        autocapitalizationType = .none
        isSecureTextEntry = true
    }

    public func resetToSentinel() {
        text = Self.sentinel
    }

    // MARK: - Input accessory bar (docs/08 §3.2)

    /// Supplies the accessory bar's content view, already wrapped by the SwiftUI side's own
    /// `UIHostingController` — `KeyInputHostRepresentable`'s coordinator sets this. This class
    /// never imports SwiftUI itself; only the resulting `UIView` crosses the boundary (docs/08
    /// §3.2: "the UIKit class stays free of SwiftUI imports except for `UIHostingController`" —
    /// this design keeps it free of SwiftUI entirely, since even `UIHostingController` lives on
    /// the representable's side).
    public var accessoryContentProvider: (() -> UIView?)? {
        didSet {
            cachedAccessoryInputView = nil
            reloadInputViews()
        }
    }

    private var cachedAccessoryInputView: UIInputView?

    /// Replaces the previous "Done"-only `UIToolbar` with a `UIInputView` hosting the SwiftUI
    /// `KeyboardAccessoryBar` (docs/08 §3.2): five tab icons, a gear, and a trailing Done, all
    /// height 44 pt with a material background supplied by the hosted content itself.
    public override var inputAccessoryView: UIView? {
        get {
            if let cachedAccessoryInputView { return cachedAccessoryInputView }
            guard let content = accessoryContentProvider?() else { return nil }
            let inputView = UIInputView(frame: CGRect(x: 0, y: 0, width: 0, height: 44), inputViewStyle: .keyboard)
            inputView.allowsSelfSizing = true
            content.translatesAutoresizingMaskIntoConstraints = false
            inputView.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
                content.topAnchor.constraint(equalTo: inputView.topAnchor),
                content.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
                content.heightAnchor.constraint(equalToConstant: 44),
            ])
            cachedAccessoryInputView = inputView
            return inputView
        }
        set { /* fixed; content comes from accessoryContentProvider */ }
    }

    /// Hides the software keyboard — called from the accessory bar's Done button, or after a tab
    /// tap (docs/08 §2.2/§3.2: "Tapping a tab calls `tabSwitcher.switchTo(tab)` and resigns first
    /// responder"). Only resigns this view's own first-responder status; the delegate is
    /// responsible for the corresponding `KeyboardBridge.wantsFirstResponder = false` (see
    /// `KeyInputHostViewDelegate.keyInputHostDidRequestHide`).
    public func requestHide() {
        hostDelegate?.keyInputHostDidRequestHide(self)
        resignFirstResponder()
    }

    // MARK: - UIKeyInput capture (spec §4.4.2)

    /// Pure IME gate (spec §4.4.2: "if `markedTextRange != nil` → return (IME composing)"),
    /// factored out for testability — see file header.
    public nonisolated static func shouldForwardTextEvent(hasMarkedText: Bool) -> Bool {
        !hasMarkedText
    }

    public override func insertText(_ text: String) {
        guard Self.shouldForwardTextEvent(hasMarkedText: markedTextRange != nil) else {
            super.insertText(text)
            return
        }
        guard !text.isEmpty else { return }
        if text == "\n" {
            // Return key: forward as a key event, not text (spec §4.4.2 "Return key (\n) →
            // key{code: 0x24, tap}").
            hostDelegate?.keyInputHost(self, hardwareKeyEvent: HardwareKeyEvent(
                virtualKey: VirtualKey.kVK_Return, charactersIgnoringModifiers: "\r", modifiers: [], isDown: true))
            hostDelegate?.keyInputHost(self, hardwareKeyEvent: HardwareKeyEvent(
                virtualKey: VirtualKey.kVK_Return, charactersIgnoringModifiers: "\r", modifiers: [], isDown: false))
            return
        }
        hostDelegate?.keyInputHost(self, didInsertText: text)
    }

    public override func deleteBackward() {
        guard Self.shouldForwardTextEvent(hasMarkedText: markedTextRange != nil) else {
            super.deleteBackward()
            return
        }
        hostDelegate?.keyInputHostDidDeleteBackward(self)
    }

    // MARK: - Hardware passthrough (spec §4.4.6)

    public override var canBecomeFirstResponder: Bool { true }

    /// Pure HID → `VirtualKey`/`KeyModifiers` resolution plus the "should this become a `key`
    /// event rather than flow through `insertText`" policy (spec §4.4.3/§4.4.6), factored out so
    /// it is testable without a real `UIPress`/`UIKey` (neither has a public initializer).
    /// Returns `nil` when `HIDKeycodeTable` has no mapping for `hidUsage` (spec §11.2's handful of
    /// omitted keys — Print Screen, Application/Menu, F21–F24, …).
    public nonisolated static func resolveHardwareKey(
        hidUsage: UInt16, modifierFlags: UIKeyModifierFlags, charactersIgnoringModifiers: String?
    ) -> (virtualKey: UInt16, modifiers: KeyModifiers, shouldIntercept: Bool)? {
        guard let virtualKey = HIDKeycodeTable.virtualKey(forHIDUsage: hidUsage) else { return nil }
        let modifiers = KeyModifiers(uiKeyModifierFlags: modifierFlags)
        let isChord = !modifierFlags.intersection([.command, .alternate, .control]).isEmpty
        let shouldIntercept = nonPrintingHIDUsages.contains(hidUsage) || isChord
        return (virtualKey, modifiers, shouldIntercept)
    }

    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = isHardwarePassthroughEnabled ? forward(presses, isDown: true) : presses
        guard !unhandled.isEmpty else { return }
        super.pressesBegan(unhandled, with: event)
    }

    public override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = isHardwarePassthroughEnabled ? forward(presses, isDown: false) : presses
        guard !unhandled.isEmpty else { return }
        super.pressesEnded(unhandled, with: event)
    }

    public override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = isHardwarePassthroughEnabled ? forward(presses, isDown: false) : presses
        guard !unhandled.isEmpty else { return }
        super.pressesCancelled(unhandled, with: event)
    }

    /// Resolves and forwards every press that should be intercepted; returns the subset that was
    /// left alone (no mapping, or a plain printable key with no ⌘/⌃/⌥ — spec §4.4.6: "Text from a
    /// hardware keyboard without modifiers still flows through the Unicode path via `insertText`
    /// so layouts and dead keys work") so the caller can still forward those to `super`.
    private func forward(_ presses: Set<UIPress>, isDown: Bool) -> Set<UIPress> {
        var unhandled: Set<UIPress> = []
        for press in presses {
            // `UIKeyboardHIDUsage.rawValue` is `Int`; the HID usage tables (§11.2) only ever use
            // values that fit in `UInt16`.
            guard let key = press.key,
                  let hidUsage = UInt16(exactly: key.keyCode.rawValue),
                  let resolved = Self.resolveHardwareKey(
                    hidUsage: hidUsage,
                    modifierFlags: key.modifierFlags,
                    charactersIgnoringModifiers: key.charactersIgnoringModifiers),
                  resolved.shouldIntercept
            else {
                unhandled.insert(press)
                continue
            }
            if isDown {
                if heldHIDUsages.contains(hidUsage) { continue } // suppress hardware key-repeat
                heldHIDUsages.insert(hidUsage)
            } else {
                heldHIDUsages.remove(hidUsage)
            }
            let characters = key.charactersIgnoringModifiers.isEmpty ? nil : key.charactersIgnoringModifiers
            hostDelegate?.keyInputHost(self, hardwareKeyEvent: HardwareKeyEvent(
                virtualKey: resolved.virtualKey,
                charactersIgnoringModifiers: characters,
                modifiers: resolved.modifiers,
                isDown: isDown))
        }
        return unhandled
    }
}

extension KeyModifiers {
    /// Maps `UIKeyModifierFlags` (from `UIKey.modifierFlags`) to the wire's `KeyModifiers`. Caps
    /// Lock is intentionally not read from `.alphaShift` here — spec §4.4.4/FR-KB-012 makes Caps
    /// Lock the user's explicit client-side toggle (tracked by `KeyboardBridge`), not the
    /// transient hardware modifier-key state of any single press.
    public init(uiKeyModifierFlags flags: UIKeyModifierFlags) {
        var result: KeyModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.alternate) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        self = result
    }
}
