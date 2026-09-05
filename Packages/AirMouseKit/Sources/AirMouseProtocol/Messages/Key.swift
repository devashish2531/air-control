import Foundation

/// `key` (C→H). spec §3.4.5 / §11.1.
public struct Key: Codable, Sendable, Equatable {
    /// macOS virtual keycode (ANSI table, spec Appendix §11.2 — see `Keycodes/VirtualKey.swift`).
    public var code: Int
    /// Single character when the key is printable; host re-resolves to a keycode on its current
    /// input source (spec §5.3.6).
    public var char: String?
    public var action: KeyAction
    public var modifiers: KeyModifiers

    public init(code: Int, char: String? = nil, action: KeyAction, modifiers: KeyModifiers) {
        self.code = code
        self.char = char
        self.action = action
        self.modifiers = modifiers
    }
}
