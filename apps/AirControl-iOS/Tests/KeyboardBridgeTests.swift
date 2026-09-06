// Tests/KeyboardBridgeTests.swift
// `KeyInputHostView`'s HID→`VirtualKey` resolution (spec §4.4.6) and IME marked-text gating
// (spec §4.4.2) are both factored into pure static functions specifically so they're testable
// without a real `UIPress`/`UIKey` (neither has a public initializer) or a live `UITextInput`
// session (a bare `UITextView`'s `markedTextRange` only reflects IME state while it holds an
// active input session, which this test target cannot simulate) — see
// `KeyInputHostView.resolveHardwareKey` / `.shouldForwardTextEvent`'s doc comments. Secure-entry's
// autocorrect-disabling is tested directly against the real view's properties, since those don't
// require an input session.

import Testing
import UIKit
import AirControlProtocol
@testable import Air_Control

@Suite struct KeyboardBridgeTests {
    // MARK: - HID → VirtualKey mapping (letters, arrows, F-keys)

    @Test func lettersMapToTheirVirtualKey() {
        // 'a' = HID usage 0x04 (spec §11.2).
        let resolved = KeyInputHostView.resolveHardwareKey(hidUsage: 0x04, modifierFlags: [], charactersIgnoringModifiers: "a")
        #expect(resolved?.virtualKey == VirtualKey.kVK_ANSI_A)
        // A plain letter with no ⌘/⌃/⌥ is NOT intercepted — it flows through `insertText`
        // instead (spec §4.4.3/§4.4.6).
        #expect(resolved?.shouldIntercept == false)
    }

    @Test func shiftAloneDoesNotForceInterception() {
        // Shift is excluded from the "chord forces key path" trio (spec §4.4.3: "any chord with
        // ⌘/⌃/⌥"); shift+letter should still take the Unicode path so layouts produce the
        // correct uppercase character.
        let resolved = KeyInputHostView.resolveHardwareKey(hidUsage: 0x04, modifierFlags: [.shift], charactersIgnoringModifiers: "a")
        #expect(resolved?.shouldIntercept == false)
        #expect(resolved?.modifiers == [.shift])
    }

    @Test func commandChordForcesInterception() {
        let resolved = KeyInputHostView.resolveHardwareKey(hidUsage: 0x06, modifierFlags: [.command], charactersIgnoringModifiers: "c")
        #expect(resolved?.virtualKey == VirtualKey.kVK_ANSI_C)
        #expect(resolved?.shouldIntercept == true)
        #expect(resolved?.modifiers == [.command])
    }

    @Test func arrowsMapAndAlwaysIntercept() {
        // Left arrow = HID usage 0x50 (spec §11.2).
        let resolved = KeyInputHostView.resolveHardwareKey(hidUsage: 0x50, modifierFlags: [], charactersIgnoringModifiers: nil)
        #expect(resolved?.virtualKey == VirtualKey.kVK_LeftArrow)
        #expect(resolved?.shouldIntercept == true)
    }

    @Test func fKeysMapAndAlwaysIntercept() {
        // F1 = HID usage 0x3A (spec §11.2).
        let resolved = KeyInputHostView.resolveHardwareKey(hidUsage: 0x3A, modifierFlags: [], charactersIgnoringModifiers: nil)
        #expect(resolved?.virtualKey == VirtualKey.kVK_F1)
        #expect(resolved?.shouldIntercept == true)
    }

    @Test func unmappedHIDUsageReturnsNil() {
        // Print Screen (0x46) has no macOS kVK_* equivalent (spec §11.2's omitted keys).
        let resolved = KeyInputHostView.resolveHardwareKey(hidUsage: 0x46, modifierFlags: [], charactersIgnoringModifiers: nil)
        #expect(resolved == nil)
    }

    @Test func modifierFlagConversionUnionsEveryFlag() {
        let resolved = KeyInputHostView.resolveHardwareKey(
            hidUsage: 0x04, modifierFlags: [.command, .alternate, .control, .shift], charactersIgnoringModifiers: "a")
        #expect(resolved?.modifiers == [.command, .option, .control, .shift])
    }

    // MARK: - IME marked-text gating (fake text-input state)

    @Test func textEventsAreForwardedWhenNoMarkedText() {
        #expect(KeyInputHostView.shouldForwardTextEvent(hasMarkedText: false) == true)
    }

    @Test func textEventsAreGatedWhileComposing() {
        // Simulates the fake text input's marked-text state directly, matching spec §4.4.2:
        // "if markedTextRange != nil → return (IME composing)".
        #expect(KeyInputHostView.shouldForwardTextEvent(hasMarkedText: true) == false)
    }

    // MARK: - Secure entry disables autocorrect/prediction (spec §4.1.6 eye-slash toggle)

    @MainActor
    @Test func secureEntryDisablesAutocorrectAndPrediction() {
        let view = KeyInputHostView()
        view.configureForCommitMode() // start from the "everything on" baseline
        view.configureForSecureEntry()
        #expect(view.autocorrectionType == .no)
        #expect(view.spellCheckingType == .no)
        #expect(view.smartQuotesType == .no)
        #expect(view.smartDashesType == .no)
        #expect(view.smartInsertDeleteType == .no)
        #expect(view.autocapitalizationType == .none)
        #expect(view.isSecureTextEntry == true)
    }

    @MainActor
    @Test func liveModeAlsoDisablesAutocorrect() {
        let view = KeyInputHostView()
        view.configureForLiveMode()
        #expect(view.autocorrectionType == .no)
        #expect(view.isSecureTextEntry == false)
    }

    @MainActor
    @Test func commitModeFollowsSystemDefaults() {
        let view = KeyInputHostView()
        view.configureForCommitMode()
        #expect(view.autocorrectionType == .default)
        #expect(view.isSecureTextEntry == false)
    }
}
