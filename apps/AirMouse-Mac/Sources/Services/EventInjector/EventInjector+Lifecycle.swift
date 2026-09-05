// EventInjector+Lifecycle — spec §5.3.11 "Release-all and lifecycle":
// "`releaseAll()` posts `mouseUp` for every held button, `flagsChanged` up for every latched
// modifier, `keyUp` for every repeating key, stops momentum and text queues." Triggered (by the
// caller — session stale/close, `goodbye`, revoke, pause, Accessibility loss, sleep, quit, the
// held-input watchdog) from outside this module; `EventInjector` only implements the release itself
// plus the `pause()` case (spec §5.3.10), which calls this directly.
import AirMouseProtocol
import CoreGraphics

extension EventInjector {
    public func releaseAll() async {
        releaseHeldButtons()
        releaseLatchedModifiers()
        releaseRepeatingKeys()
        cancelTextQueue()
        cancelScheduledTaps()
        await momentumEngine.cancel()
        remainder = .zero
        scrollRemainder = .zero
        scrollSessionOpen = false
    }

    private func releaseHeldButtons() {
        for button in heldButtons.sorted(by: { $0.rawValue < $1.rawValue }) {
            if let event = mouseClickEvent(button: button, isDown: false, position: virtualPos, clickState: 1) {
                _ = postSigned(event, category: .click)
            }
        }
        heldButtons.removeAll()
    }

    private func releaseLatchedModifiers() {
        guard !latchedModifiers.isEmpty else { return }
        var cumulative = latchedModifiers
        for modifier in Self.orderedModifiers where cumulative.contains(modifier) {
            cumulative.remove(modifier)
            postModifierKeyEvent(modifier: modifier, isDown: false, cumulative: cumulative)
        }
        latchedModifiers = []
    }

    private func releaseRepeatingKeys() {
        for (keycode, timer) in repeatingKeys {
            timer.cancel()
            if let event = CGEvent(keyboardEventSource: source, virtualKey: keycode, keyDown: false) {
                event.flags = currentCGEventFlags()
                _ = postSigned(event, category: .key)
            }
        }
        repeatingKeys.removeAll()
    }

    private func cancelScheduledTaps() {
        for (_, timer) in scheduledTimers {
            timer.cancel()
        }
        scheduledTimers.removeAll()
    }
}
