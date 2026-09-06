import Foundation

/// `click` (C→H). spec §3.4.5 / §11.1.
public struct Click: Codable, Sendable, Equatable {
    public var button: MouseButton
    public var action: ClickAction
    /// 1–3 → `mouseEventClickState`; host clamps to 1 if the previous click of the same button was
    /// > 1.5 × `doubleClickIntervalMs` ago.
    public var count: Int
    public var modifiers: KeyModifiers

    public init(button: MouseButton, action: ClickAction, count: Int, modifiers: KeyModifiers) {
        self.button = button
        self.action = action
        self.count = count
        self.modifiers = modifiers
    }
}
