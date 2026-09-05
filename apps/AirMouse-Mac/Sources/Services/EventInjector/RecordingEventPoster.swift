// RecordingEventPoster — records a `Sendable` `PostedEvent` for every call instead of posting to
// WindowServer. Used by this target's tests (so `EventInjector`/`MomentumEngine` are fully testable
// on a machine without Accessibility granted — spec §10.2) and by the app's `--loopback` mode
// (`LaunchArguments.loopback`), which needs to run the full injection pipeline for local development
// and screenshots without actually taking over the mouse/keyboard.
//
// `final class` with all mutable state behind `OSAllocatedUnfairLock` (the `KeycodeMapper` pattern) so
// this conforms to `Sendable` directly — no `@unchecked Sendable` (CLAUDE.md / architecture §5.1 allow
// exactly two documented `nonisolated(unsafe)` sites elsewhere in the kit; this isn't one of them, and
// doesn't need to be).
import AirMouseProtocol
import CoreGraphics
import os

public final class RecordingEventPoster: EventPosting, Sendable {
    private let state = OSAllocatedUnfairLock(initialState: [PostedEvent]())

    public init() {}

    /// All events recorded so far, in post order.
    public var events: [PostedEvent] {
        state.withLock { $0 }
    }

    /// The most recently recorded event, if any.
    public var lastEvent: PostedEvent? {
        state.withLock { $0.last }
    }

    public func removeAll() {
        state.withLock { $0.removeAll() }
    }

    public func post(_ event: CGEvent) {
        // `describe` must run before entering the `@Sendable` lock closure: `CGEvent` itself is not
        // `Sendable`, only the `PostedEvent` snapshot extracted from it is.
        let posted = Self.describe(event)
        state.withLock { $0.append(posted) }
    }

    public func postSystemDefined(nxKeyType: Int32, isKeyDown: Bool) {
        let posted = PostedEvent(kind: .systemDefinedKey, nxKeyType: nxKeyType, isKeyDown: isKeyDown)
        state.withLock { $0.append(posted) }
    }

    /// Extracts a `Sendable` snapshot of the fields spec §5.3 requires `EventInjector` to have set,
    /// reading them synchronously off the live `CGEvent` (never retaining the event itself).
    private static func describe(_ event: CGEvent) -> PostedEvent {
        let type = event.type
        var posted = PostedEvent(
            kind: Self.kind(for: event, type: type),
            location: event.location,
            flags: event.flags.rawValue
        )
        switch type {
        case .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
             .rightMouseDown, .rightMouseUp, .rightMouseDragged,
             .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            posted.deltaX = Int(event.getIntegerValueField(.mouseEventDeltaX))
            posted.deltaY = Int(event.getIntegerValueField(.mouseEventDeltaY))
            posted.buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            posted.clickState = Int(event.getIntegerValueField(.mouseEventClickState))
        case .scrollWheel:
            // `.scrollWheelEventDeltaAxis1/2` is the legacy "line" delta CoreGraphics derives from
            // the pixel value (roughly ÷10, verified empirically against this SDK) — not what
            // `EventInjector` actually passed as `wheel1`/`wheel2`. `.scrollWheelEventPointDeltaAxis1/2`
            // (a `Double` field) is the one that round-trips the exact `.pixel`-unit value the
            // constructor was given, so that is what tests need to see.
            posted.scrollWheel1 = Int(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1).rounded())
            posted.scrollWheel2 = Int(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2).rounded())
            posted.scrollIsContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            posted.scrollPhase = Int(event.getIntegerValueField(.scrollWheelEventScrollPhase))
            posted.scrollMomentumPhase = Int(event.getIntegerValueField(.scrollWheelEventMomentumPhase))
        case .keyDown, .keyUp, .flagsChanged:
            posted.keycode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            posted.unicodeString = Self.unicodeString(from: event)
        default:
            break
        }
        return posted
    }

    /// A `CGEvent` built via `CGEvent(keyboardEventSource:virtualKey:keyDown:)` for a *modifier's own*
    /// virtual keycode (⌘ 0x37, ⌥ 0x3A, ⌃ 0x3B, ⇧ 0x38, fn 0x3F — spec §5.3.6) comes back with
    /// `event.type == .flagsChanged`, not `.keyDown`/`.keyUp` — CoreGraphics recognizes those keycodes
    /// as modifier keys and reclassifies the type at construction time regardless of the `keyDown`
    /// argument passed in (verified empirically; matches how the real HID/WindowServer pipeline has no
    /// separate "modifier key up/down" event type of its own). Since `.flagsChanged` carries no
    /// down/up bit of its own — the OS itself distinguishes press from release only by diffing
    /// `flags` against the previous state — recover it the same way here: `postModifierKeyEvent`
    /// always sets `event.flags` to the *cumulative* mask *after* this change (spec §5.3.6's "diff
    /// with current set ... with the cumulative flag mask"), so the modifier's own mask bit is present
    /// in `flags` exactly when this is the down event.
    private static func kind(for event: CGEvent, type: CGEventType) -> PostedEventKind {
        guard type == .flagsChanged else { return PostedEventKind(cgEventType: type) }
        let keycode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard let mask = Self.modifierMask(forVirtualKeycode: keycode) else { return .other }
        return event.flags.contains(mask) ? .keyDown : .keyUp
    }

    /// The `CGEventFlags` bit `EventInjector.cgFlags(_:)` sets for each modifier virtual keycode
    /// (spec §5.3.6) — `capsLock` shares ⇧'s keycode/mask, so no separate case is needed.
    private static func modifierMask(forVirtualKeycode keycode: UInt16) -> CGEventFlags? {
        switch keycode {
        case VirtualKey.kVK_Command: .maskCommand
        case VirtualKey.kVK_Option: .maskAlternate
        case VirtualKey.kVK_Control: .maskControl
        case VirtualKey.kVK_Shift: .maskShift
        case VirtualKey.kVK_Function: .maskSecondaryFn
        default: nil
        }
    }

    /// Reads back whatever Unicode text a `keyboardSetUnicodeString` call put on this event (spec
    /// §5.3.6 `text{s}` path); empty for ordinary virtual-key events.
    private static func unicodeString(from event: CGEvent) -> String? {
        var actualLength = 0
        event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &actualLength, unicodeString: nil)
        guard actualLength > 0 else { return nil }
        var units = [UniChar](repeating: 0, count: actualLength)
        event.keyboardGetUnicodeString(maxStringLength: actualLength, actualStringLength: &actualLength, unicodeString: &units)
        return String(utf16CodeUnits: units, count: actualLength)
    }
}
