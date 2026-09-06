// MediaKey — the wire's `mediaKey.key` enum, backed by the NX_KEYTYPE_* system-defined key codes.
//
// spec §11.1 (`mediaKey` (C→H): `key` enum(playPause|next|previous|fastForward|rewind|volumeUp|
// volumeDown|mute|brightnessUp|brightnessDown|illuminationUp|illuminationDown)) and §5.3.7 (host
// posts `NSEvent.otherEvent(.systemDefined, subtype: 8, data1: (NX_KEYTYPE << 16) | ...)`, listing
// the NX constants: SOUND_UP 0, SOUND_DOWN 1, BRIGHTNESS_UP 2, BRIGHTNESS_DOWN 3, MUTE 7, PLAY 16,
// NEXT 17, PREVIOUS 18, FAST 19, REWIND 20, ILLUMINATION_UP 21, ILLUMINATION_DOWN 22 — matching
// `IOKit/hidsystem/ev_keymap.h`'s `NX_KEYTYPE_*` constants (docs/02-technical-research.md).
///
/// `rawValue` is the `NX_KEYTYPE_*` system-defined key code the Mac host needs to post the event
/// (spec §5.3.7); wire JSON encoding is the camelCase case name via a custom `Codable`
/// implementation, matching the wire enum in spec §11.1 (not the raw NX integer).
public enum MediaKey: Int32, CaseIterable, Sendable {
    case volumeUp = 0 // NX_KEYTYPE_SOUND_UP
    case volumeDown = 1 // NX_KEYTYPE_SOUND_DOWN
    case brightnessUp = 2 // NX_KEYTYPE_BRIGHTNESS_UP
    case brightnessDown = 3 // NX_KEYTYPE_BRIGHTNESS_DOWN
    case mute = 7 // NX_KEYTYPE_MUTE
    case playPause = 16 // NX_KEYTYPE_PLAY
    case next = 17 // NX_KEYTYPE_NEXT
    case previous = 18 // NX_KEYTYPE_PREVIOUS
    case fastForward = 19 // NX_KEYTYPE_FAST
    case rewind = 20 // NX_KEYTYPE_REWIND
    case illuminationUp = 21 // NX_KEYTYPE_ILLUMINATION_UP
    case illuminationDown = 22 // NX_KEYTYPE_ILLUMINATION_DOWN

    /// The `NX_KEYTYPE_*` system-defined key code, for `data1 = (nxKeyType << 16) | ...` (spec §5.3.7).
    public var nxKeyType: Int32 { rawValue }

    /// The wire's camelCase name for this key (spec §11.1's `mediaKey.key` enum).
    public var wireName: String {
        switch self {
        case .playPause: "playPause"
        case .next: "next"
        case .previous: "previous"
        case .fastForward: "fastForward"
        case .rewind: "rewind"
        case .volumeUp: "volumeUp"
        case .volumeDown: "volumeDown"
        case .mute: "mute"
        case .brightnessUp: "brightnessUp"
        case .brightnessDown: "brightnessDown"
        case .illuminationUp: "illuminationUp"
        case .illuminationDown: "illuminationDown"
        }
    }
}

extension MediaKey: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let match = Self.allCases.first(where: { $0.wireName == name }) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown mediaKey.key value: \(name)"
            )
        }
        self = match
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wireName)
    }
}
