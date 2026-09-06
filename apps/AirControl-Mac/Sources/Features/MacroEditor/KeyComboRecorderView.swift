// spec §5.5.3: "Key combo recorder (a focused `NSView` with `NSEvent.addLocalMonitorForEvents(matching:
// [.keyDown, .flagsChanged]) active only while the editor window is key — no global monitor; displays
// the macOS glyph string, stores `keyCode + modifiers + keyLabel` from the current layout)".
import AirControlProtocol
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A button that, while armed, installs a **local** key-event monitor (never a global `CGEventTap` —
/// this app has no Input Monitoring entitlement and must not request one, research §A7) to capture the
/// next chord and report it back as `(modifiers, keyCode, glyph)`.
struct KeyComboRecorderView: View {
    var currentGlyph: String
    var onRecorded: (KeyModifiers, UInt16, String) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            HStack {
                Image(systemName: isRecording ? "record.circle.fill" : "keyboard")
                    .foregroundStyle(isRecording ? .red : .secondary)
                Text(isRecording ? "Press a key…" : (currentGlyph.isEmpty ? "Click to record" : currentGlyph))
                    .monospaced()
            }
            .frame(minWidth: 160)
        }
        .buttonStyle(.bordered)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        guard monitor == nil else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Only a plain keyDown carries a keycode we want to store as the "shortcut key"; a
            // `flagsChanged`-only event (the user let go without pressing a key) is ignored so the
            // recorder keeps listening.
            guard event.type == .keyDown else { return event }
            let modifiers = KeyModifiers(event.modifierFlags)
            let glyph = KeyGlyph.string(forKeyCode: event.keyCode, modifiers: modifiers)
            onRecorded(modifiers, event.keyCode, glyph)
            stopRecording()
            return nil // swallow — this keystroke configures a macro, it should not also type/act
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
    }
}

private extension KeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var result: KeyModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.function) { result.insert(.function) }
        if flags.contains(.capsLock) { result.insert(.capsLock) }
        self = result
    }
}

/// Builds the "macOS glyph string" spec §5.5.3 calls for — e.g. `⌃⌘Q`, `⌘⇧4`, `fn F11`. HIG modifier
/// order is ⌃⌥⇧⌘; `fn` isn't a real modifier glyph so it's rendered as the literal word, prefixed
/// (matching how spec §5.5.2's starter set writes "fn F11").
enum KeyGlyph {
    static func string(forKeyCode keyCode: UInt16, modifiers: KeyModifiers) -> String {
        var prefix = ""
        var hasFn = false
        if modifiers.contains(.function) { hasFn = true }
        if modifiers.contains(.control) { prefix += "⌃" }
        if modifiers.contains(.option) { prefix += "⌥" }
        if modifiers.contains(.shift) { prefix += "⇧" }
        if modifiers.contains(.command) { prefix += "⌘" }

        let keyName = Self.keyNames[keyCode] ?? Self.fallbackName(forKeyCode: keyCode)
        if hasFn {
            return prefix.isEmpty ? "fn \(keyName)" : "fn \(prefix)\(keyName)"
        }
        return "\(prefix)\(keyName)"
    }

    // Same `UCKeyTranslate` recipe `KeycodeMapper` uses to build its reverse table (spec §5.3.6);
    // here it runs in the other direction (one keycode → its printable character) just to produce a
    // human-legible label for a key the recorder doesn't have a name for in `keyNames`.
    private static func fallbackName(forKeyCode keyCode: UInt16) -> String {
        guard
            let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutDataPointer = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData)
        else {
            return "Key \(keyCode)"
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPointer).takeUnretainedValue()
        let keyboardType = UInt32(LMGetKbdType())

        var result = "Key \(keyCode)"
        (layoutData as Data).withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            guard let layoutPointer = rawBuffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return
            }
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layoutPointer,
                keyCode,
                UInt16(kUCKeyActionDown),
                0,
                keyboardType,
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
            guard status == noErr, length > 0 else { return }
            result = String(utf16CodeUnits: chars, count: length).uppercased()
        }
        return result
    }

    /// Special keys that don't have (or shouldn't use) a printable-character glyph.
    private static let keyNames: [UInt16: String] = [
        VirtualKey.kVK_Return: "↩",
        VirtualKey.kVK_Tab: "⇥",
        VirtualKey.kVK_Space: "Space",
        VirtualKey.kVK_Delete: "⌫",
        VirtualKey.kVK_ForwardDelete: "⌦",
        VirtualKey.kVK_Escape: "⎋",
        VirtualKey.kVK_Home: "Home",
        VirtualKey.kVK_End: "End",
        VirtualKey.kVK_PageUp: "Page Up",
        VirtualKey.kVK_PageDown: "Page Down",
        VirtualKey.kVK_LeftArrow: "←",
        VirtualKey.kVK_RightArrow: "→",
        VirtualKey.kVK_DownArrow: "↓",
        VirtualKey.kVK_UpArrow: "↑",
        VirtualKey.kVK_F1: "F1", VirtualKey.kVK_F2: "F2", VirtualKey.kVK_F3: "F3", VirtualKey.kVK_F4: "F4",
        VirtualKey.kVK_F5: "F5", VirtualKey.kVK_F6: "F6", VirtualKey.kVK_F7: "F7", VirtualKey.kVK_F8: "F8",
        VirtualKey.kVK_F9: "F9", VirtualKey.kVK_F10: "F10", VirtualKey.kVK_F11: "F11", VirtualKey.kVK_F12: "F12",
    ]
}
