// Tests for AirControlProtocol/Keycodes/*. spec §11.2 (keycode table), §11.1 (`mediaKey`, `modifiers`).
import Foundation
import Testing
@testable import AirControlProtocol

@Suite struct HIDKeycodeTableTests {
    // Every row of the spec §11.2 table, verified verbatim.
    @Test(arguments: [
        (UInt16(0x04), VirtualKey.kVK_ANSI_A), (0x05, VirtualKey.kVK_ANSI_B), (0x06, VirtualKey.kVK_ANSI_C),
        (0x07, VirtualKey.kVK_ANSI_D), (0x08, VirtualKey.kVK_ANSI_E), (0x09, VirtualKey.kVK_ANSI_F),
        (0x0A, VirtualKey.kVK_ANSI_G), (0x0B, VirtualKey.kVK_ANSI_H), (0x0C, VirtualKey.kVK_ANSI_I),
        (0x0D, VirtualKey.kVK_ANSI_J), (0x0E, VirtualKey.kVK_ANSI_K), (0x0F, VirtualKey.kVK_ANSI_L),
        (0x10, VirtualKey.kVK_ANSI_M), (0x11, VirtualKey.kVK_ANSI_N), (0x12, VirtualKey.kVK_ANSI_O),
        (0x13, VirtualKey.kVK_ANSI_P), (0x14, VirtualKey.kVK_ANSI_Q), (0x15, VirtualKey.kVK_ANSI_R),
        (0x16, VirtualKey.kVK_ANSI_S), (0x17, VirtualKey.kVK_ANSI_T), (0x18, VirtualKey.kVK_ANSI_U),
        (0x19, VirtualKey.kVK_ANSI_V), (0x1A, VirtualKey.kVK_ANSI_W), (0x1B, VirtualKey.kVK_ANSI_X),
        (0x1C, VirtualKey.kVK_ANSI_Y), (0x1D, VirtualKey.kVK_ANSI_Z),
        (0x1E, VirtualKey.kVK_ANSI_1), (0x1F, VirtualKey.kVK_ANSI_2), (0x20, VirtualKey.kVK_ANSI_3),
        (0x21, VirtualKey.kVK_ANSI_4), (0x22, VirtualKey.kVK_ANSI_5), (0x23, VirtualKey.kVK_ANSI_6),
        (0x24, VirtualKey.kVK_ANSI_7), (0x25, VirtualKey.kVK_ANSI_8), (0x26, VirtualKey.kVK_ANSI_9),
        (0x27, VirtualKey.kVK_ANSI_0),
        (0x28, VirtualKey.kVK_Return), (0x29, VirtualKey.kVK_Escape), (0x2A, VirtualKey.kVK_Delete),
        (0x2B, VirtualKey.kVK_Tab), (0x2C, VirtualKey.kVK_Space), (0x2D, VirtualKey.kVK_ANSI_Minus),
        (0x2E, VirtualKey.kVK_ANSI_Equal), (0x2F, VirtualKey.kVK_ANSI_LeftBracket),
        (0x30, VirtualKey.kVK_ANSI_RightBracket), (0x31, VirtualKey.kVK_ANSI_Backslash),
        (0x33, VirtualKey.kVK_ANSI_Semicolon), (0x34, VirtualKey.kVK_ANSI_Quote),
        (0x35, VirtualKey.kVK_ANSI_Grave), (0x36, VirtualKey.kVK_ANSI_Comma),
        (0x37, VirtualKey.kVK_ANSI_Period), (0x38, VirtualKey.kVK_ANSI_Slash),
        (0x39, VirtualKey.kVK_CapsLock), (0x64, VirtualKey.kVK_ISO_Section),
        (0x3A, VirtualKey.kVK_F1), (0x3B, VirtualKey.kVK_F2), (0x3C, VirtualKey.kVK_F3),
        (0x3D, VirtualKey.kVK_F4), (0x3E, VirtualKey.kVK_F5), (0x3F, VirtualKey.kVK_F6),
        (0x40, VirtualKey.kVK_F7), (0x41, VirtualKey.kVK_F8), (0x42, VirtualKey.kVK_F9),
        (0x43, VirtualKey.kVK_F10), (0x44, VirtualKey.kVK_F11), (0x45, VirtualKey.kVK_F12),
        (0x49, VirtualKey.kVK_Help), (0x4A, VirtualKey.kVK_Home), (0x4B, VirtualKey.kVK_PageUp),
        (0x4C, VirtualKey.kVK_ForwardDelete), (0x4D, VirtualKey.kVK_End), (0x4E, VirtualKey.kVK_PageDown),
        (0x4F, VirtualKey.kVK_RightArrow), (0x50, VirtualKey.kVK_LeftArrow),
        (0x51, VirtualKey.kVK_DownArrow), (0x52, VirtualKey.kVK_UpArrow),
        (0x58, VirtualKey.kVK_ANSI_KeypadEnter), (0x62, VirtualKey.kVK_ANSI_Keypad0),
        (0xE0, VirtualKey.kVK_Control), (0xE1, VirtualKey.kVK_Shift), (0xE2, VirtualKey.kVK_Option),
        (0xE3, VirtualKey.kVK_Command), (0xE4, VirtualKey.kVK_RightControl),
        (0xE5, VirtualKey.kVK_RightShift), (0xE6, VirtualKey.kVK_RightOption),
        (0xE7, VirtualKey.kVK_RightCommand),
    ] as [(UInt16, UInt16)])
    func specTableRow(hid: UInt16, expectedVK: UInt16) {
        #expect(HIDKeycodeTable.virtualKey(forHIDUsage: hid) == expectedVK)
    }

    @Test func keypadDigitRunSkipsF20() {
        // spec §11.2: HID 0x59–0x61 (keypad 1–9) → kVK 0x53–0x5C, but kVK 0x5A is F20, not a keypad
        // digit — the real Carbon layout skips it, so the HID run of 9 codes still lands on 9 kVKs.
        let expected: [UInt16] = [
            VirtualKey.kVK_ANSI_Keypad1, VirtualKey.kVK_ANSI_Keypad2, VirtualKey.kVK_ANSI_Keypad3,
            VirtualKey.kVK_ANSI_Keypad4, VirtualKey.kVK_ANSI_Keypad5, VirtualKey.kVK_ANSI_Keypad6,
            VirtualKey.kVK_ANSI_Keypad7, VirtualKey.kVK_ANSI_Keypad8, VirtualKey.kVK_ANSI_Keypad9,
        ]
        let actual = (0x59...0x61).map { HIDKeycodeTable.virtualKey(forHIDUsage: UInt16($0)) }
        #expect(actual == expected)
        #expect(!expected.contains(VirtualKey.kVK_F20))
    }

    @Test func unmappedUsageReturnsNil() {
        #expect(HIDKeycodeTable.virtualKey(forHIDUsage: 0x46) == nil) // PrintScreen
        #expect(HIDKeycodeTable.virtualKey(forHIDUsage: 0x65) == nil) // Application/Menu
    }

    @Test func reverseTableRoundTrips() {
        let cases: [(hid: UInt16, vk: UInt16)] = [
            (0x04, VirtualKey.kVK_ANSI_A),
            (0x28, VirtualKey.kVK_Return),
            (0xE3, VirtualKey.kVK_Command),
            (0x3A, VirtualKey.kVK_F1),
        ]
        for testCase in cases {
            #expect(HIDKeycodeTable.hidUsage(forVirtualKey: testCase.vk) == testCase.hid)
        }
    }

    @Test func fRowUpToF20IsMapped() {
        let fKeyHIDUsages: [UInt16] = Array(0x3A...0x45) + Array(0x68...0x6F)
        #expect(fKeyHIDUsages.count == 20)
        for hid in fKeyHIDUsages {
            #expect(HIDKeycodeTable.virtualKey(forHIDUsage: hid) != nil)
        }
    }
}

@Suite struct VirtualKeyTests {
    @Test func modifierPairsAreDistinctBothSides() {
        #expect(VirtualKey.kVK_Command != VirtualKey.kVK_RightCommand)
        #expect(VirtualKey.kVK_Shift != VirtualKey.kVK_RightShift)
        #expect(VirtualKey.kVK_Option != VirtualKey.kVK_RightOption)
        #expect(VirtualKey.kVK_Control != VirtualKey.kVK_RightControl)
    }
}

@Suite struct MediaKeyTests {
    @Test(arguments: [
        (MediaKey.volumeUp, Int32(0)), (.volumeDown, 1), (.brightnessUp, 2), (.brightnessDown, 3),
        (.mute, 7), (.playPause, 16), (.next, 17), (.previous, 18), (.fastForward, 19), (.rewind, 20),
        (.illuminationUp, 21), (.illuminationDown, 22),
    ])
    func nxKeyTypeMatchesSpec(key: MediaKey, expectedNX: Int32) {
        #expect(key.nxKeyType == expectedNX)
        #expect(key.rawValue == expectedNX)
    }

    @Test func codableRoundTripsAsWireString() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for key in MediaKey.allCases {
            let data = try encoder.encode(key)
            let json = String(decoding: data, as: UTF8.self)
            #expect(json == "\"\(key.wireName)\"")
            let decoded = try decoder.decode(MediaKey.self, from: data)
            #expect(decoded == key)
        }
    }

    @Test func unknownWireStringFailsToDecode() {
        let data = Data("\"notARealKey\"".utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(MediaKey.self, from: data)
        }
    }
}

@Suite struct KeyModifiersTests {
    @Test func codableEncodesAsWireArray() throws {
        let modifiers: KeyModifiers = [.command, .shift]
        let data = try JSONEncoder().encode(modifiers)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json == "[\"cmd\",\"shift\"]")
    }

    @Test func codableDecodesWireArray() throws {
        let data = Data("[\"ctrl\",\"opt\",\"fn\",\"capsLock\"]".utf8)
        let decoded = try JSONDecoder().decode(KeyModifiers.self, from: data)
        #expect(decoded == [.control, .option, .function, .capsLock])
    }

    @Test func emptyArrayRoundTrips() throws {
        let data = try JSONEncoder().encode(KeyModifiers())
        #expect(String(decoding: data, as: UTF8.self) == "[]")
        let decoded = try JSONDecoder().decode(KeyModifiers.self, from: data)
        #expect(decoded.isEmpty)
    }

    @Test func unknownWireStringFailsToDecode() {
        let data = Data("[\"notARealModifier\"]".utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(KeyModifiers.self, from: data)
        }
    }

    @Test func modifierVirtualKeycodesMatchSpec() {
        // spec §5.3.6: "⌘ 0x37, ⌥ 0x3A, ⌃ 0x3B, ⇧ 0x38, fn 0x3F, caps as ⇧ flag"
        #expect(KeyModifiers.command.virtualKeycode == 0x37)
        #expect(KeyModifiers.option.virtualKeycode == 0x3A)
        #expect(KeyModifiers.control.virtualKeycode == 0x3B)
        #expect(KeyModifiers.shift.virtualKeycode == 0x38)
        #expect(KeyModifiers.function.virtualKeycode == 0x3F)
        #expect(KeyModifiers.capsLock.virtualKeycode == KeyModifiers.shift.virtualKeycode)
    }
}
