// EventInjector+Keyboard — spec §5.3.6 (keyboard): virtual-key events, auto-repeat, modifier latch,
// arbitrary Unicode text, and backspace/forward-delete bursts.
import AirControlProtocol
import AppKit
import CoreGraphics
import Dispatch

extension EventInjector {
    /// spec §5.3.6: "Post `CGEvent(keyboardEventSource:virtualKey:keyDown:)` with `flags` = requested
    /// modifiers ∪ latched; `down` also starts auto-repeat ...; `up` stops it." `char`, when present,
    /// is resolved against the current keyboard layout via `KeycodeMapper.resolve(code:char:)` (only
    /// takes effect on a non-ANSI layout — see that type's doc comment); `virtualKey` is the fallback
    /// wire `code`.
    public func key(virtualKey: UInt16, char: String? = nil, modifiers: KeyModifiers, isDown: Bool) {
        guard !paused else {
            counters.droppedWhilePaused += 1
            return
        }
        noteActivity()

        let resolved = keycodeMapper?.resolve(code: virtualKey, char: char) ?? virtualKey
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: resolved, keyDown: isDown) else { return }
        event.flags = currentCGEventFlags(additional: modifiers)
        guard postSigned(event, category: .key) else { return }
        counters.keysPosted += 1

        if isDown {
            startRepeat(keycode: resolved, modifiers: modifiers)
        } else {
            stopRepeat(keycode: resolved)
        }
    }

    /// spec §5.3.6: "`tap` = down + up 8 ms later."
    public func keyTap(virtualKey: UInt16, char: String? = nil, modifiers: KeyModifiers) {
        key(virtualKey: virtualKey, char: char, modifiers: modifiers, isDown: true)
        scheduleAfter(Self.keyTapGap) { isolated in
            isolated.key(virtualKey: virtualKey, char: char, modifiers: modifiers, isDown: false)
        }
    }

    static let orderedModifiers: [KeyModifiers] = [.command, .option, .control, .shift, .function, .capsLock]

    /// spec §5.3.6 `modifiers{flags}`: "diff with current set; for each newly held modifier post
    /// `flagsChanged` keyDown of the modifier keycode ... with the cumulative flag mask; for each
    /// released, the keyUp. Flags persist onto subsequent clicks/keys/moves." (Research A3: these are
    /// ordinary keyDown/keyUp `CGEvent`s for the modifier's own virtual keycode — WindowServer/AppKit
    /// deliver them as `flagsChanged` to observers — not a distinct `CGEventType`.)
    public func setModifiers(_ flags: KeyModifiers) {
        guard !paused else {
            counters.droppedWhilePaused += 1
            return
        }
        noteActivity()

        let added = flags.subtracting(latchedModifiers)
        let removed = latchedModifiers.subtracting(flags)
        var cumulative = latchedModifiers
        for modifier in Self.orderedModifiers where added.contains(modifier) {
            cumulative.insert(modifier)
            postModifierKeyEvent(modifier: modifier, isDown: true, cumulative: cumulative)
        }
        for modifier in Self.orderedModifiers where removed.contains(modifier) {
            cumulative.remove(modifier)
            postModifierKeyEvent(modifier: modifier, isDown: false, cumulative: cumulative)
        }
        latchedModifiers = flags
    }

    func postModifierKeyEvent(modifier: KeyModifiers, isDown: Bool, cumulative: KeyModifiers) {
        guard let keycode = modifier.virtualKeycode,
              let event = CGEvent(keyboardEventSource: source, virtualKey: keycode, keyDown: isDown)
        else { return }
        event.flags = cgFlags(cumulative)
        guard postSigned(event, category: .key) else { return }
        counters.keysPosted += 1
    }

    // MARK: - Auto-repeat (spec §5.3.6: "400 ms then every 40 ms, using NSEvent.keyRepeatDelay/Interval
    // when the user's values are smaller")

    func startRepeat(keycode: UInt16, modifiers: KeyModifiers) {
        stopRepeat(keycode: keycode)
        let initialDelay = min(Self.keyRepeatDelayCeiling, NSEvent.keyRepeatDelay)
        let interval = min(Self.keyRepeatIntervalCeiling, NSEvent.keyRepeatInterval)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + initialDelay, repeating: interval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.assumeIsolated { isolated in
                isolated.postRepeatKeyDown(keycode: keycode, modifiers: modifiers)
            }
        }
        repeatingKeys[keycode] = timer
        timer.resume()
    }

    func stopRepeat(keycode: UInt16) {
        repeatingKeys[keycode]?.cancel()
        repeatingKeys.removeValue(forKey: keycode)
    }

    private func postRepeatKeyDown(keycode: UInt16, modifiers: KeyModifiers) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keycode, keyDown: true) else { return }
        event.flags = currentCGEventFlags(additional: modifiers)
        // spec §5.3.9: "keys 60/s (excluding repeats)" — repeats intentionally do not count against
        // `counters.keysPosted`'s rate-limiter category the same way a fresh key does; they still go
        // through the signpost/post path.
        _ = postSigned(event, category: .key)
    }

    // MARK: - deleteBackward (spec §5.3.6: "`count` × keycode 0x33 (or 0x75) taps at 2 ms spacing")

    public func deleteBackward(count: Int, forward: Bool) async {
        guard !paused else {
            counters.droppedWhilePaused += 1
            return
        }
        let keycode: UInt16 = forward ? VirtualKey.kVK_ForwardDelete : VirtualKey.kVK_Delete
        for _ in 0..<max(0, count) {
            guard !paused else { break }
            keyTap(virtualKey: keycode, char: nil, modifiers: [])
            try? await Task.sleep(nanoseconds: UInt64(Self.deleteBackwardSpacing * 1_000_000_000))
        }
    }

    // MARK: - Arbitrary Unicode text (spec §5.3.6 `text{s}`)

    /// Chunks into UTF-16 runs, keyDowns each with `keyboardSetUnicodeString`, paces chunks so the
    /// overall rate stays ≤ `textRateCharsPerSecond` (min 1 ms gap), and — because this actor has no
    /// per-session identity yet (see `HeldInputLedger`'s TODO(integration)) — serializes ALL calls to
    /// `typeText` host-wide via a chained `Task`, so two sessions' text can never interleave
    /// mid-pacing even though "a text queue is per session" in the spec's wording.
    public func typeText(_ text: String) async {
        guard !paused else {
            counters.droppedWhilePaused += 1
            return
        }
        let previous = textQueueTail
        let task = Task { [weak self] in
            _ = await previous?.value
            guard let self else { return }
            await self.performTypeText(text)
        }
        textQueueTail = task
        await task.value
    }

    /// spec §5.3.11: "stops ... text queues" on release-all. Best-effort: cancels the tail of the
    /// chain; a chunk already in flight finishes its current `postUnicodeChunk` but the loop checks
    /// `Task.isCancelled`/`paused` between chunks and stops promptly.
    func cancelTextQueue() {
        textQueueTail?.cancel()
        textQueueTail = nil
    }

    private func performTypeText(_ text: String) async {
        noteActivity()
        for chunk in Self.chunkedForTyping(text, maxUTF16Units: Self.textChunkUTF16Units) {
            guard !paused, !Task.isCancelled else { return }
            postUnicodeChunk(chunk)
            counters.textCharactersPosted += chunk.count
            let gapSeconds = max(0.001, Double(chunk.count) / textRateCharsPerSecond)
            try? await Task.sleep(nanoseconds: UInt64(gapSeconds * 1_000_000_000))
        }
    }

    private func postUnicodeChunk(_ units: [UInt16]) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else { return }
        var mutableUnits = units
        down.keyboardSetUnicodeString(stringLength: mutableUnits.count, unicodeString: &mutableUnits)
        down.flags = currentCGEventFlags()
        guard postSigned(down, category: .text) else { return }
        guard let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }
        up.flags = currentCGEventFlags()
        _ = postSigned(up, category: .text)
    }

    /// Splits `text` into UTF-16 runs of at most `maxUTF16Units` units, never splitting a `Character`
    /// (Swift's grapheme cluster) or, in the rare fallback path for a single grapheme cluster longer
    /// than the chunk size, a UTF-16 surrogate pair (spec §5.3.6: "never splitting a surrogate pair or
    /// a grapheme cluster where avoidable").
    static func chunkedForTyping(_ text: String, maxUTF16Units: Int) -> [[UInt16]] {
        var chunks: [[UInt16]] = []
        var current: [UInt16] = []
        for character in text {
            let units = Array(String(character).utf16)
            if units.count > maxUTF16Units {
                if !current.isEmpty {
                    chunks.append(current)
                    current = []
                }
                var index = 0
                while index < units.count {
                    var end = min(index + maxUTF16Units, units.count)
                    if end < units.count, UTF16.isTrailSurrogate(units[end]) {
                        end -= 1
                    }
                    chunks.append(Array(units[index..<end]))
                    index = end
                }
                continue
            }
            if current.count + units.count > maxUTF16Units {
                chunks.append(current)
                current = []
            }
            current.append(contentsOf: units)
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }
}

// MARK: - KeyEventEmitting (Services/MacroEngine/KeyEventEmitting.swift)

extension EventInjector: KeyEventEmitting {
    /// `KeyEventEmitting.press`: a chorded tap (down, modifiers held, up 8 ms later — same path as an
    /// ordinary `key` message tap, spec §5.3.6).
    public func press(virtualKey: UInt16, modifiers: KeyModifiers) async {
        keyTap(virtualKey: virtualKey, char: nil, modifiers: modifiers)
    }
}
