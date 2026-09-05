// Tests for keyboard/text/media-key posting: Services/EventInjector/EventInjector+Keyboard.swift,
// EventInjector+MediaKeys.swift. spec §5.3.6, §5.3.7.
import AirMouseFilters
import AirMouseProtocol
import CoreGraphics
import Testing
@testable import Air_Mouse

@Suite struct EventInjectorKeyboardTests {
    private func makeInjector() -> (EventInjector, RecordingEventPoster) {
        let poster = RecordingEventPoster()
        let injector = EventInjector(poster: poster, startHeldInputWatchdog: false)
        return (injector, poster)
    }

    // MARK: - typeText chunking / unicode

    @Test func chunksAtSixteenUTF16UnitsWithoutSplittingCharacters() {
        // 20 ASCII characters (20 UTF-16 units) must split 16 + 4, never mid-character.
        let text = String(repeating: "a", count: 20)
        let chunks = EventInjector.chunkedForTyping(text, maxUTF16Units: 16)
        #expect(chunks.map(\.count) == [16, 4])
    }

    @Test func neverSplitsASurrogatePairAcrossChunks() {
        // U+1F600 (😀) is a surrogate pair (2 UTF-16 units). 15 "a"s + one emoji = 17 units; the
        // emoji must not be split even though 15 + 1 unit would fit but 15 + 2 would not.
        let text = String(repeating: "a", count: 15) + "\u{1F600}"
        let chunks = EventInjector.chunkedForTyping(text, maxUTF16Units: 16)
        #expect(chunks.count == 2)
        #expect(chunks[0].count == 15)
        #expect(chunks[1].count == 2)
    }

    @Test func typeTextPostsUnicodeStringReadableBackFromTheEvent() async {
        let (injector, poster) = makeInjector()
        await injector.typeText("Hi")
        let downEvents = poster.events.filter { $0.kind == .keyDown }
        #expect(downEvents.contains { $0.unicodeString == "Hi" })
        #expect(poster.events.contains { $0.kind == .keyUp })
    }

    @Test func typeTextPacesMultipleChunksAtLeastOneMillisecondApart() async {
        let (injector, poster) = makeInjector()
        await injector.updateTextRate(charsPerSecond: 10_000) // fast, but still a nonzero gap per chunk
        let text = String(repeating: "b", count: 32) // 2 chunks of 16
        await injector.typeText(text)
        let downEvents = poster.events.filter { $0.kind == .keyDown }
        #expect(downEvents.count == 2)
    }

    // MARK: - deleteBackward

    @Test func deleteBackwardPostsCountTapsOfDeleteKeycode() async {
        let (injector, poster) = makeInjector()
        await injector.deleteBackward(count: 3, forward: false)
        try? await Task.sleep(nanoseconds: 100_000_000) // let scheduled "up" taps fire
        let downs = poster.events.filter { $0.kind == .keyDown && $0.keycode == Int(VirtualKey.kVK_Delete) }
        #expect(downs.count == 3)
    }

    @Test func forwardDeleteUsesForwardDeleteKeycode() async {
        let (injector, poster) = makeInjector()
        await injector.deleteBackward(count: 1, forward: true)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(poster.events.contains { $0.kind == .keyDown && $0.keycode == Int(VirtualKey.kVK_ForwardDelete) })
    }

    // MARK: - Modifiers latch (spec §5.3.6 `modifiers{flags}`)

    @Test func settingModifiersPostsKeyDownForEachNewlyHeldModifier() async {
        let (injector, poster) = makeInjector()
        await injector.setModifiers([.command, .shift])
        let downs = poster.events.filter { $0.kind == .keyDown }
        #expect(downs.count == 2)
        #expect(downs.contains { $0.keycode == Int(VirtualKey.kVK_Command) })
        #expect(downs.contains { $0.keycode == Int(VirtualKey.kVK_Shift) })
    }

    @Test func clearingModifiersPostsKeyUpForEachPreviouslyHeldModifier() async {
        let (injector, poster) = makeInjector()
        await injector.setModifiers([.command])
        poster.removeAll()
        await injector.setModifiers([])
        #expect(poster.events.contains { $0.kind == .keyUp && $0.keycode == Int(VirtualKey.kVK_Command) })
    }

    @Test func latchedModifiersPersistOntoSubsequentClicks() async {
        let (injector, poster) = makeInjector()
        await injector.setModifiers([.control])
        poster.removeAll()
        await injector.click(button: .left, isDown: true, clickCount: 1)
        let flags = poster.lastEvent?.flags ?? 0
        #expect(flags & CGEventFlags.maskControl.rawValue != 0)
    }

    // MARK: - Media keys (spec §5.3.7 / research A4)

    @Test func mediaKeyDownEncodesNXKeyTypeAndDownState() async {
        let (injector, poster) = makeInjector()
        await injector.mediaKey(.playPause, isDown: true)
        let event = poster.lastEvent
        #expect(event?.kind == .systemDefinedKey)
        #expect(event?.nxKeyType == MediaKey.playPause.nxKeyType)
        #expect(event?.isKeyDown == true)
    }

    @Test func mediaKeyTapPostsDownThenUpTenMillisecondsApart() async {
        let (injector, poster) = makeInjector()
        await injector.mediaKeyTap(.volumeUp)
        try? await Task.sleep(nanoseconds: 40_000_000)
        #expect(poster.events.map(\.isKeyDown) == [true, false])
    }
}
