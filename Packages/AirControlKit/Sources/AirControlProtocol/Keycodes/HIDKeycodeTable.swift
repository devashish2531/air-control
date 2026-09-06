// HIDKeycodeTable — USB HID usage page 0x07 (Keyboard/Keypad) → macOS virtual keycode (kVK_*).
//
// spec §11.2 (Appendix — keycode table): the normative subset (letters, digits, punctuation, the
// nav cluster, F1–F12, both-side modifiers, ISO section, keypad 0 and keypad enter) is reproduced
// verbatim from the spec table below; the remaining ~90 entries (F13–F20, the rest of the keypad,
// JIS-only keys, volume/mute) fill in the "full ~110-entry table" the appendix describes without
// spelling out, derived from the same USB HID Usage Tables document (usage page 0x07) that produced
// the spec's own rows — every HID usage the spec *does* list resolves to the exact kVK the spec
// gives it (cross-checked entry by entry against §11.2 while building this table).
//
// Used by `KeyInputHostView` hardware passthrough (spec §4.4.6, `UIKeyboardHIDUsage` → this table
// → macOS keycode) and by the Mac `KeycodeMapper` fallback path (spec §5.3.6).
public enum HIDKeycodeTable {
    /// USB HID usage page 0x07 usage ID → macOS virtual keycode.
    private static let hidToVirtualKey: [UInt16: UInt16] = [
        // Letters (spec §11.2)
        0x04: VirtualKey.kVK_ANSI_A,
        0x05: VirtualKey.kVK_ANSI_B,
        0x06: VirtualKey.kVK_ANSI_C,
        0x07: VirtualKey.kVK_ANSI_D,
        0x08: VirtualKey.kVK_ANSI_E,
        0x09: VirtualKey.kVK_ANSI_F,
        0x0A: VirtualKey.kVK_ANSI_G,
        0x0B: VirtualKey.kVK_ANSI_H,
        0x0C: VirtualKey.kVK_ANSI_I,
        0x0D: VirtualKey.kVK_ANSI_J,
        0x0E: VirtualKey.kVK_ANSI_K,
        0x0F: VirtualKey.kVK_ANSI_L,
        0x10: VirtualKey.kVK_ANSI_M,
        0x11: VirtualKey.kVK_ANSI_N,
        0x12: VirtualKey.kVK_ANSI_O,
        0x13: VirtualKey.kVK_ANSI_P,
        0x14: VirtualKey.kVK_ANSI_Q,
        0x15: VirtualKey.kVK_ANSI_R,
        0x16: VirtualKey.kVK_ANSI_S,
        0x17: VirtualKey.kVK_ANSI_T,
        0x18: VirtualKey.kVK_ANSI_U,
        0x19: VirtualKey.kVK_ANSI_V,
        0x1A: VirtualKey.kVK_ANSI_W,
        0x1B: VirtualKey.kVK_ANSI_X,
        0x1C: VirtualKey.kVK_ANSI_Y,
        0x1D: VirtualKey.kVK_ANSI_Z,

        // Digits (spec §11.2)
        0x1E: VirtualKey.kVK_ANSI_1,
        0x1F: VirtualKey.kVK_ANSI_2,
        0x20: VirtualKey.kVK_ANSI_3,
        0x21: VirtualKey.kVK_ANSI_4,
        0x22: VirtualKey.kVK_ANSI_5,
        0x23: VirtualKey.kVK_ANSI_6,
        0x24: VirtualKey.kVK_ANSI_7,
        0x25: VirtualKey.kVK_ANSI_8,
        0x26: VirtualKey.kVK_ANSI_9,
        0x27: VirtualKey.kVK_ANSI_0,

        // Whitespace / editing / punctuation (spec §11.2)
        0x28: VirtualKey.kVK_Return,
        0x29: VirtualKey.kVK_Escape,
        0x2A: VirtualKey.kVK_Delete,
        0x2B: VirtualKey.kVK_Tab,
        0x2C: VirtualKey.kVK_Space,
        0x2D: VirtualKey.kVK_ANSI_Minus,
        0x2E: VirtualKey.kVK_ANSI_Equal,
        0x2F: VirtualKey.kVK_ANSI_LeftBracket,
        0x30: VirtualKey.kVK_ANSI_RightBracket,
        0x31: VirtualKey.kVK_ANSI_Backslash,
        // 0x32 Non-US "#~" — no ANSI keyboard equivalent; omitted.
        0x33: VirtualKey.kVK_ANSI_Semicolon,
        0x34: VirtualKey.kVK_ANSI_Quote,
        0x35: VirtualKey.kVK_ANSI_Grave,
        0x36: VirtualKey.kVK_ANSI_Comma,
        0x37: VirtualKey.kVK_ANSI_Period,
        0x38: VirtualKey.kVK_ANSI_Slash,
        0x39: VirtualKey.kVK_CapsLock,

        // F1–F12 (spec §11.2)
        0x3A: VirtualKey.kVK_F1,
        0x3B: VirtualKey.kVK_F2,
        0x3C: VirtualKey.kVK_F3,
        0x3D: VirtualKey.kVK_F4,
        0x3E: VirtualKey.kVK_F5,
        0x3F: VirtualKey.kVK_F6,
        0x40: VirtualKey.kVK_F7,
        0x41: VirtualKey.kVK_F8,
        0x42: VirtualKey.kVK_F9,
        0x43: VirtualKey.kVK_F10,
        0x44: VirtualKey.kVK_F11,
        0x45: VirtualKey.kVK_F12,
        // 0x46 PrintScreen, 0x47 ScrollLock, 0x48 Pause — no Mac keyboard equivalent; omitted.

        // Nav cluster (spec §11.2)
        0x49: VirtualKey.kVK_Help, // Insert/Help
        0x4A: VirtualKey.kVK_Home,
        0x4B: VirtualKey.kVK_PageUp,
        0x4C: VirtualKey.kVK_ForwardDelete,
        0x4D: VirtualKey.kVK_End,
        0x4E: VirtualKey.kVK_PageDown,
        0x4F: VirtualKey.kVK_RightArrow,
        0x50: VirtualKey.kVK_LeftArrow,
        0x51: VirtualKey.kVK_DownArrow,
        0x52: VirtualKey.kVK_UpArrow,

        // Keypad (spec §11.2 gives 0x62→0x52 and the 0x59–0x61 digit run; the rest follows the
        // same USB HID Usage Tables layout)
        0x53: VirtualKey.kVK_ANSI_KeypadClear, // Num Lock / Clear
        0x54: VirtualKey.kVK_ANSI_KeypadDivide,
        0x55: VirtualKey.kVK_ANSI_KeypadMultiply,
        0x56: VirtualKey.kVK_ANSI_KeypadMinus,
        0x57: VirtualKey.kVK_ANSI_KeypadPlus,
        0x58: VirtualKey.kVK_ANSI_KeypadEnter,
        0x59: VirtualKey.kVK_ANSI_Keypad1,
        0x5A: VirtualKey.kVK_ANSI_Keypad2,
        0x5B: VirtualKey.kVK_ANSI_Keypad3,
        0x5C: VirtualKey.kVK_ANSI_Keypad4,
        0x5D: VirtualKey.kVK_ANSI_Keypad5,
        0x5E: VirtualKey.kVK_ANSI_Keypad6,
        0x5F: VirtualKey.kVK_ANSI_Keypad7,
        0x60: VirtualKey.kVK_ANSI_Keypad8,
        0x61: VirtualKey.kVK_ANSI_Keypad9,
        0x62: VirtualKey.kVK_ANSI_Keypad0,
        0x63: VirtualKey.kVK_ANSI_KeypadDecimal,
        0x64: VirtualKey.kVK_ISO_Section, // Non-US \| — spec §11.2 "ISO §"
        // 0x65 Application/Menu, 0x66 Power — no Mac equivalent; omitted.
        0x67: VirtualKey.kVK_ANSI_KeypadEquals,

        // F13–F20 (beyond spec §11.2's table, same USB HID usage page)
        0x68: VirtualKey.kVK_F13,
        0x69: VirtualKey.kVK_F14,
        0x6A: VirtualKey.kVK_F15,
        0x6B: VirtualKey.kVK_F16,
        0x6C: VirtualKey.kVK_F17,
        0x6D: VirtualKey.kVK_F18,
        0x6E: VirtualKey.kVK_F19,
        0x6F: VirtualKey.kVK_F20,
        // 0x70–0x73 F21–F24 — no Mac kVK_* equivalent; omitted.

        // Volume/mute (present on some external USB keyboards) and JIS extras
        0x7F: VirtualKey.kVK_Mute,
        0x80: VirtualKey.kVK_VolumeUp,
        0x81: VirtualKey.kVK_VolumeDown,
        0x85: VirtualKey.kVK_JIS_KeypadComma,
        0x87: VirtualKey.kVK_JIS_Underscore, // International1 ("ro" key)
        0x89: VirtualKey.kVK_JIS_Yen, // International3
        0x90: VirtualKey.kVK_JIS_Kana, // LANG1
        0x91: VirtualKey.kVK_JIS_Eisu, // LANG2

        // Modifiers, both sides (spec §11.2)
        0xE0: VirtualKey.kVK_Control, // left
        0xE1: VirtualKey.kVK_Shift, // left
        0xE2: VirtualKey.kVK_Option, // left
        0xE3: VirtualKey.kVK_Command, // left
        0xE4: VirtualKey.kVK_RightControl,
        0xE5: VirtualKey.kVK_RightShift,
        0xE6: VirtualKey.kVK_RightOption,
        0xE7: VirtualKey.kVK_RightCommand,
    ]

    /// Reverse table, built once from `hidToVirtualKey`. The forward map is injective (no two HID
    /// usages resolve to the same kVK), so this is a well-defined 1:1 inverse.
    private static let virtualKeyToHID: [UInt16: UInt16] = {
        var reversed: [UInt16: UInt16] = [:]
        reversed.reserveCapacity(hidToVirtualKey.count)
        for (hid, vk) in hidToVirtualKey {
            reversed[vk] = hid
        }
        return reversed
    }()

    /// USB HID usage page 0x07 usage ID → macOS virtual keycode, or `nil` if this table has no
    /// mapping for it (e.g. Print Screen, the Application/Menu key, F21–F24 — keys with no Mac
    /// keyboard equivalent).
    public static func virtualKey(forHIDUsage hidUsage: UInt16) -> UInt16? {
        hidToVirtualKey[hidUsage]
    }

    /// macOS virtual keycode → USB HID usage page 0x07 usage ID, the inverse of
    /// `virtualKey(forHIDUsage:)`.
    public static func hidUsage(forVirtualKey virtualKey: UInt16) -> UInt16? {
        virtualKeyToHID[virtualKey]
    }
}
