import Foundation

/// `click.button`. spec §3.4.5: "enum(left|right|middle)".
public enum MouseButton: String, Codable, Sendable, Equatable, CaseIterable {
    case left
    case right
    case middle
}
