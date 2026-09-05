import Foundation

/// `mediaKey` (C→H). spec §3.4.5: "`key` enum(playPause|next|previous|fastForward|rewind|
/// volumeUp|volumeDown|mute|brightnessUp|brightnessDown|illuminationUp|illuminationDown),
/// `action` enum(tap|down|up)."
///
/// Named `MediaKeyMessage` (not `MediaKey`) because `Keycodes/MediaKey.swift` already defines
/// `MediaKey` as the `key` enum itself (backed by the `NX_KEYTYPE_*` constants the Mac host needs
/// to post the event, per spec §5.3.7) — this struct reuses that type rather than redefining it.
public struct MediaKeyMessage: Codable, Sendable, Equatable {
    public var key: MediaKey
    public var action: MediaKeyAction

    public init(key: MediaKey, action: MediaKeyAction) {
        self.key = key
        self.action = action
    }
}
