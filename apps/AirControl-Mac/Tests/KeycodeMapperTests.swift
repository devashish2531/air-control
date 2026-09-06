// Tests for Services/KeycodeMapper/KeycodeMapper.swift. spec §5.3.6, architecture §3.3.
//
// These run against whatever keyboard layout is selected on the machine executing the test, so
// they assert the ANSI fallback path when the layout is non-ANSI and the direct reverse-table path
// otherwise, rather than hardcoding a US layout assumption.
import Testing
@testable import Air_Control
import AirControlProtocol
import Carbon.HIToolbox

/// Translates `keyCode` with no modifiers on the machine's current keyboard layout, independent of
/// `KeycodeMapper`, so tests can check the mapper's output against an oracle instead of hardcoding
/// a US-layout assumption.
private func unmodifiedCharacter(forKeyCode keyCode: UInt16) -> Character? {
    guard
        let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
        let layoutDataPointer = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData)
    else { return nil }
    let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPointer).takeUnretainedValue() as Data
    var result: Character?
    layoutData.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
        guard let layoutPointer = rawBuffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
            return
        }
        var deadKeyState: UInt32 = 0
        var unicodeChars = [UniChar](repeating: 0, count: 4)
        var actualLength = 0
        let status = UCKeyTranslate(
            layoutPointer, keyCode, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
            OptionBits(0), &deadKeyState, unicodeChars.count, &actualLength, &unicodeChars
        )
        guard status == noErr, actualLength == 1, let scalar = Unicode.Scalar(unicodeChars[0]) else { return }
        result = Character(scalar)
    }
    return result
}

@Suite struct KeycodeMapperTests {
    @Test func lettersAndDigitsResolveViaLayout() {
        let mapper = KeycodeMapper()

        if mapper.isANSILayout {
            // spec §5.3.6: on an ANSI-compatible layout the wire's `code` is authoritative
            // regardless of `char` — the reverse table is not consulted.
            #expect(mapper.resolve(code: VirtualKey.kVK_ANSI_Q, char: "a") == VirtualKey.kVK_ANSI_Q)
            #expect(mapper.resolve(code: VirtualKey.kVK_ANSI_A, char: nil) == VirtualKey.kVK_ANSI_A)
        } else {
            // Non-ANSI layout: `char` must resolve through the current layout's reverse table
            // rather than falling back to the (almost certainly wrong) US ANSI `code`. Use the
            // oracle above to find some letter this layout actually produces unmodified, then
            // confirm the mapper resolves that character to the keycode that produces it.
            let wrongCode = VirtualKey.kVK_ANSI_Semicolon
            var foundACharacterToCheck = false
            for keyCode in UInt16(0)...UInt16(50) {
                guard let character = unmodifiedCharacter(forKeyCode: keyCode), character.isLetter else { continue }
                foundACharacterToCheck = true
                let resolved = mapper.resolve(code: wrongCode, char: String(character))
                #expect(resolved == keyCode)
                break
            }
            #expect(foundACharacterToCheck, "expected at least one letter key on this non-ANSI layout")
        }
    }

    @Test func nilCharFallsBackToCode() {
        let mapper = KeycodeMapper()
        #expect(mapper.resolve(code: VirtualKey.kVK_ANSI_Z, char: nil) == VirtualKey.kVK_ANSI_Z)
    }

    @Test func emptyCharFallsBackToCode() {
        let mapper = KeycodeMapper()
        #expect(mapper.resolve(code: VirtualKey.kVK_Space, char: "") == VirtualKey.kVK_Space)
    }

    @Test func multiCharacterStringFallsBackToCode() {
        // spec's `char` field is "single character when the key is printable" (§11.1); a
        // multi-character string is not a valid `char` payload, so treat it like "absent".
        let mapper = KeycodeMapper()
        #expect(mapper.resolve(code: VirtualKey.kVK_ANSI_A, char: "ab") == VirtualKey.kVK_ANSI_A)
    }

    @Test func ansiFlagIsStableAcrossCalls() {
        let mapper = KeycodeMapper()
        let first = mapper.isANSILayout
        let second = mapper.isANSILayout
        #expect(first == second)
    }

    @Test func concurrentResolvesDoNotCrash() async {
        let mapper = KeycodeMapper()
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<200 {
                group.addTask {
                    _ = mapper.resolve(code: VirtualKey.kVK_ANSI_A, char: i.isMultiple(of: 2) ? "a" : nil)
                }
            }
        }
    }
}
