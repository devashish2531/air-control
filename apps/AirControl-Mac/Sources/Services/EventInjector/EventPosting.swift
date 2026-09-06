// EventPosting — the seam between `EventInjector` (CGEvent construction, spec §5.3) and where the
// fully-built event actually goes: real WindowServer delivery (`CGEventPoster`) or an in-memory,
// `Sendable` recording (`RecordingEventPoster`, spec §10.2's `RecordingInjector` idea, scoped here to
// just the posting step) used by both this target's tests and the app's `--loopback` mode
// (`LaunchArguments.loopback`, owned by the CLI/app-shell agent).
//
// Kept deliberately synchronous (no `async`, neither type is an `actor`) so `EventInjector` — itself
// a custom-executor actor (spec §5.2/§5.3.1) — can call straight through on its own dedicated queue
// with zero additional hops, matching architecture §3.3 "decrypt → accelerate → post happens on one
// thread with zero hops" for the motion path, and §5.3's "All posts to `.cghidEventTap` from the
// inject queue; never from the main thread."
import AppKit
import CoreGraphics

/// Where a constructed `CGEvent` (mouse/scroll/keyboard) or a media/system-defined key event actually
/// goes. `EventInjector` is the only caller; it never posts a `CGEvent` itself.
public protocol EventPosting: Sendable {
    /// Posts a fully-configured mouse, scroll, or keyboard `CGEvent` to `.cghidEventTap` (spec §5.3.1).
    /// `EventInjector` always sets every field the spec requires (deltas, click state, scroll
    /// phase/momentum, flags, keycode/unicode) before calling this — implementations only post or
    /// record what they are given.
    func post(_ event: CGEvent)

    /// Posts a media/system-defined key event (spec §5.3.7): an `NSEvent(.systemDefined, subtype: 8,
    /// data1: (nxKeyType << 16) | state, data2: -1)`'s `cgEvent`. Kept separate from `post(_:)` — the
    /// event is built from `NSEvent`, not `CGEvent`, and a recorder should not need to reconstruct an
    /// `NSEvent` just to read back the two integers that matter (`nxKeyType`, `isKeyDown`).
    func postSystemDefined(nxKeyType: Int32, isKeyDown: Bool)
}

// MARK: - CGEventPoster (production)

/// Posts to the real HID event tap. Holds no mutable state (the `CGEventSource` and per-host pointer
/// state live on `EventInjector`), so it is trivially, non-`@unchecked`, `Sendable`.
public final class CGEventPoster: EventPosting, Sendable {
    public init() {}

    public func post(_ event: CGEvent) {
        event.post(tap: .cghidEventTap)
    }

    /// spec §5.3.7 / research A4: `data1 = (nxKeyType << 16) | (down ? 0xa00 : 0xb00 keyState-nibble)`.
    /// `0xa`/`0xb` are the low byte of the down/up "key state" nibble the long-standing convention
    /// packs into `data1`'s second byte; `data2` is always `-1`; `timestamp` is always `0` (matches
    /// every open-source implementation of this technique — the value is unused by the recipient).
    public func postSystemDefined(nxKeyType: Int32, isKeyDown: Bool) {
        let modifierFlags = isKeyDown ? 0xa00 : 0xb00
        let stateNibble = isKeyDown ? 0xa : 0xb
        let data1 = Int((Int(nxKeyType) << 16) | (stateNibble << 8))
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(modifierFlags)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }
}

// MARK: - PostedEvent (Sendable description recorded by RecordingEventPoster)

/// What kind of event `RecordingEventPoster` recorded — mirrors `CGEventType`/the media-key path
/// without exposing CoreGraphics's own (not reliably `Sendable` across SDKs) types in the record.
public enum PostedEventKind: Sendable, Equatable {
    case mouseMoved
    case leftMouseDown, leftMouseUp, leftMouseDragged
    case rightMouseDown, rightMouseUp, rightMouseDragged
    case otherMouseDown, otherMouseUp, otherMouseDragged
    case scrollWheel
    case keyDown, keyUp
    case systemDefinedKey
    case other
}

/// A `Sendable` snapshot of one posted (or, in tests, would-be-posted) event, extracted from the
/// `CGEvent`'s integer/flags fields at record time (spec §5.3: deltas, click state, scroll
/// units/phase/momentum, keycode/flags/unicode) or, for media keys, from `postSystemDefined`'s raw
/// arguments directly. Every field beyond `kind`/`location`/`flags` is optional — only the fields
/// relevant to that `kind` are populated.
public struct PostedEvent: Sendable, Equatable {
    public var kind: PostedEventKind
    public var location: CGPoint
    /// Raw `CGEventFlags.rawValue` (modifier mask) carried by the event, if any.
    public var flags: UInt64

    // Mouse move/drag/click
    public var deltaX: Int?
    public var deltaY: Int?
    public var buttonNumber: Int?
    public var clickState: Int?

    // Scroll (spec §3.6, §5.3.4)
    public var scrollWheel1: Int?
    public var scrollWheel2: Int?
    public var scrollIsContinuous: Bool?
    public var scrollPhase: Int?
    public var scrollMomentumPhase: Int?

    // Keyboard (spec §5.3.6)
    public var keycode: Int?
    public var unicodeString: String?

    // Media / system-defined (spec §5.3.7)
    public var nxKeyType: Int32?
    public var isKeyDown: Bool?

    public init(
        kind: PostedEventKind,
        location: CGPoint = .zero,
        flags: UInt64 = 0,
        deltaX: Int? = nil,
        deltaY: Int? = nil,
        buttonNumber: Int? = nil,
        clickState: Int? = nil,
        scrollWheel1: Int? = nil,
        scrollWheel2: Int? = nil,
        scrollIsContinuous: Bool? = nil,
        scrollPhase: Int? = nil,
        scrollMomentumPhase: Int? = nil,
        keycode: Int? = nil,
        unicodeString: String? = nil,
        nxKeyType: Int32? = nil,
        isKeyDown: Bool? = nil
    ) {
        self.kind = kind
        self.location = location
        self.flags = flags
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.buttonNumber = buttonNumber
        self.clickState = clickState
        self.scrollWheel1 = scrollWheel1
        self.scrollWheel2 = scrollWheel2
        self.scrollIsContinuous = scrollIsContinuous
        self.scrollPhase = scrollPhase
        self.scrollMomentumPhase = scrollMomentumPhase
        self.keycode = keycode
        self.unicodeString = unicodeString
        self.nxKeyType = nxKeyType
        self.isKeyDown = isKeyDown
    }
}

extension PostedEventKind {
    /// Maps a `CGEventType` to our `Sendable` kind; `.other` for anything `EventInjector` never emits.
    init(cgEventType: CGEventType) {
        switch cgEventType {
        case .mouseMoved: self = .mouseMoved
        case .leftMouseDown: self = .leftMouseDown
        case .leftMouseUp: self = .leftMouseUp
        case .leftMouseDragged: self = .leftMouseDragged
        case .rightMouseDown: self = .rightMouseDown
        case .rightMouseUp: self = .rightMouseUp
        case .rightMouseDragged: self = .rightMouseDragged
        case .otherMouseDown: self = .otherMouseDown
        case .otherMouseUp: self = .otherMouseUp
        case .otherMouseDragged: self = .otherMouseDragged
        case .scrollWheel: self = .scrollWheel
        case .keyDown: self = .keyDown
        case .keyUp: self = .keyUp
        default: self = .other
        }
    }
}
