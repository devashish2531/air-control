import Foundation

/// `text` (C→H). spec §3.4.5: "`s` str (1–16 384 bytes UTF-8, grapheme clusters never split across
/// messages), `secure` bool (host disables its own debug echo; no other effect on the wire)."
public struct Text: Codable, Sendable, Equatable {
    public var s: String
    public var secure: Bool

    public init(s: String, secure: Bool) {
        self.s = s
        self.secure = secure
    }
}
