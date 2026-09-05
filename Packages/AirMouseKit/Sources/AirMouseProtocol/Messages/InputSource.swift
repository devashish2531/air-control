import Foundation

/// `hostState.inputSource`. spec §3.4.5: "{`id` str, `ansi` bool} |
/// `TISCopyCurrentKeyboardLayoutInputSource`".
public struct InputSource: Codable, Sendable, Equatable {
    public var id: String
    public var ansi: Bool

    public init(id: String, ansi: Bool) {
        self.id = id
        self.ansi = ansi
    }
}
