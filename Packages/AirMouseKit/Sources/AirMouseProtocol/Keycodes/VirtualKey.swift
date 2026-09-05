// VirtualKey — macOS virtual keycode (kVK_*) constants.
//
// These mirror the constants Carbon's `HIToolbox/Events.h` defines (the `kVK_*` family), reproduced
// here so `AirMouseProtocol` (Foundation-only, no Carbon import) and every other module — including
// the iOS app, which cannot import Carbon at all — can reference them by name instead of hardcoding
// magic numbers (CLAUDE.md: "every wire constant comes from AirMouseProtocol constants, never
// literals in apps"). Names match the Carbon constants exactly (including the `kVK_` prefix) so they
// are trivially greppable against Apple's headers and the wire keycode table in spec §11.2.
//
// spec §11.2 (Appendix — keycode table), §5.3.6 (keyboard injection), §4.4.6 (hardware passthrough).
public enum VirtualKey {
    // MARK: Letters

    public static let kVK_ANSI_A: UInt16 = 0x00
    public static let kVK_ANSI_B: UInt16 = 0x0B
    public static let kVK_ANSI_C: UInt16 = 0x08
    public static let kVK_ANSI_D: UInt16 = 0x02
    public static let kVK_ANSI_E: UInt16 = 0x0E
    public static let kVK_ANSI_F: UInt16 = 0x03
    public static let kVK_ANSI_G: UInt16 = 0x05
    public static let kVK_ANSI_H: UInt16 = 0x04
    public static let kVK_ANSI_I: UInt16 = 0x22
    public static let kVK_ANSI_J: UInt16 = 0x26
    public static let kVK_ANSI_K: UInt16 = 0x28
    public static let kVK_ANSI_L: UInt16 = 0x25
    public static let kVK_ANSI_M: UInt16 = 0x2E
    public static let kVK_ANSI_N: UInt16 = 0x2D
    public static let kVK_ANSI_O: UInt16 = 0x1F
    public static let kVK_ANSI_P: UInt16 = 0x23
    public static let kVK_ANSI_Q: UInt16 = 0x0C
    public static let kVK_ANSI_R: UInt16 = 0x0F
    public static let kVK_ANSI_S: UInt16 = 0x01
    public static let kVK_ANSI_T: UInt16 = 0x11
    public static let kVK_ANSI_U: UInt16 = 0x20
    public static let kVK_ANSI_V: UInt16 = 0x09
    public static let kVK_ANSI_W: UInt16 = 0x0D
    public static let kVK_ANSI_X: UInt16 = 0x07
    public static let kVK_ANSI_Y: UInt16 = 0x10
    public static let kVK_ANSI_Z: UInt16 = 0x06

    // MARK: Digits (top row)

    public static let kVK_ANSI_0: UInt16 = 0x1D
    public static let kVK_ANSI_1: UInt16 = 0x12
    public static let kVK_ANSI_2: UInt16 = 0x13
    public static let kVK_ANSI_3: UInt16 = 0x14
    public static let kVK_ANSI_4: UInt16 = 0x15
    public static let kVK_ANSI_5: UInt16 = 0x17
    public static let kVK_ANSI_6: UInt16 = 0x16
    public static let kVK_ANSI_7: UInt16 = 0x1A
    public static let kVK_ANSI_8: UInt16 = 0x1C
    public static let kVK_ANSI_9: UInt16 = 0x19

    // MARK: Punctuation

    public static let kVK_ANSI_Equal: UInt16 = 0x18
    public static let kVK_ANSI_Minus: UInt16 = 0x1B
    public static let kVK_ANSI_RightBracket: UInt16 = 0x1E
    public static let kVK_ANSI_LeftBracket: UInt16 = 0x21
    public static let kVK_ANSI_Quote: UInt16 = 0x27
    public static let kVK_ANSI_Semicolon: UInt16 = 0x29
    public static let kVK_ANSI_Backslash: UInt16 = 0x2A
    public static let kVK_ANSI_Comma: UInt16 = 0x2B
    public static let kVK_ANSI_Slash: UInt16 = 0x2C
    public static let kVK_ANSI_Period: UInt16 = 0x2F
    public static let kVK_ANSI_Grave: UInt16 = 0x32
    public static let kVK_ISO_Section: UInt16 = 0x0A

    // MARK: Whitespace / editing

    public static let kVK_Return: UInt16 = 0x24
    public static let kVK_Tab: UInt16 = 0x30
    public static let kVK_Space: UInt16 = 0x31
    public static let kVK_Delete: UInt16 = 0x33 // backspace
    public static let kVK_ForwardDelete: UInt16 = 0x75
    public static let kVK_Escape: UInt16 = 0x35
    public static let kVK_CapsLock: UInt16 = 0x39

    // MARK: Modifiers (both sides)

    public static let kVK_Command: UInt16 = 0x37 // left
    public static let kVK_RightCommand: UInt16 = 0x36
    public static let kVK_Shift: UInt16 = 0x38 // left
    public static let kVK_RightShift: UInt16 = 0x3C
    public static let kVK_Option: UInt16 = 0x3A // left
    public static let kVK_RightOption: UInt16 = 0x3D
    public static let kVK_Control: UInt16 = 0x3B // left
    public static let kVK_RightControl: UInt16 = 0x3E
    public static let kVK_Function: UInt16 = 0x3F

    // MARK: Navigation cluster / arrows

    public static let kVK_Home: UInt16 = 0x73
    public static let kVK_End: UInt16 = 0x77
    public static let kVK_PageUp: UInt16 = 0x74
    public static let kVK_PageDown: UInt16 = 0x79
    public static let kVK_Help: UInt16 = 0x72 // also Insert
    public static let kVK_LeftArrow: UInt16 = 0x7B
    public static let kVK_RightArrow: UInt16 = 0x7C
    public static let kVK_DownArrow: UInt16 = 0x7D
    public static let kVK_UpArrow: UInt16 = 0x7E

    // MARK: Function row (F1–F20)

    public static let kVK_F1: UInt16 = 0x7A
    public static let kVK_F2: UInt16 = 0x78
    public static let kVK_F3: UInt16 = 0x63
    public static let kVK_F4: UInt16 = 0x76
    public static let kVK_F5: UInt16 = 0x60
    public static let kVK_F6: UInt16 = 0x61
    public static let kVK_F7: UInt16 = 0x62
    public static let kVK_F8: UInt16 = 0x64
    public static let kVK_F9: UInt16 = 0x65
    public static let kVK_F10: UInt16 = 0x6D
    public static let kVK_F11: UInt16 = 0x67
    public static let kVK_F12: UInt16 = 0x6F
    public static let kVK_F13: UInt16 = 0x69
    public static let kVK_F14: UInt16 = 0x6B
    public static let kVK_F15: UInt16 = 0x71
    public static let kVK_F16: UInt16 = 0x6A
    public static let kVK_F17: UInt16 = 0x40
    public static let kVK_F18: UInt16 = 0x4F
    public static let kVK_F19: UInt16 = 0x50
    public static let kVK_F20: UInt16 = 0x5A

    // MARK: Keypad

    public static let kVK_ANSI_Keypad0: UInt16 = 0x52
    public static let kVK_ANSI_Keypad1: UInt16 = 0x53
    public static let kVK_ANSI_Keypad2: UInt16 = 0x54
    public static let kVK_ANSI_Keypad3: UInt16 = 0x55
    public static let kVK_ANSI_Keypad4: UInt16 = 0x56
    public static let kVK_ANSI_Keypad5: UInt16 = 0x57
    public static let kVK_ANSI_Keypad6: UInt16 = 0x58
    public static let kVK_ANSI_Keypad7: UInt16 = 0x59
    public static let kVK_ANSI_Keypad8: UInt16 = 0x5B
    public static let kVK_ANSI_Keypad9: UInt16 = 0x5C
    public static let kVK_ANSI_KeypadDecimal: UInt16 = 0x41
    public static let kVK_ANSI_KeypadMultiply: UInt16 = 0x43
    public static let kVK_ANSI_KeypadPlus: UInt16 = 0x45
    public static let kVK_ANSI_KeypadClear: UInt16 = 0x47
    public static let kVK_ANSI_KeypadDivide: UInt16 = 0x4B
    public static let kVK_ANSI_KeypadEnter: UInt16 = 0x4C
    public static let kVK_ANSI_KeypadMinus: UInt16 = 0x4E
    public static let kVK_ANSI_KeypadEquals: UInt16 = 0x51

    // MARK: JIS-only keys

    public static let kVK_JIS_Yen: UInt16 = 0x5D
    public static let kVK_JIS_Underscore: UInt16 = 0x5E
    public static let kVK_JIS_KeypadComma: UInt16 = 0x5F
    public static let kVK_JIS_Eisu: UInt16 = 0x66
    public static let kVK_JIS_Kana: UInt16 = 0x68

    // MARK: Media (present as ordinary kVK_* on Apple keyboards' function row substitutes)

    public static let kVK_VolumeUp: UInt16 = 0x48
    public static let kVK_VolumeDown: UInt16 = 0x49
    public static let kVK_Mute: UInt16 = 0x4A
}
