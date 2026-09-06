import Foundation

/// `key.action`. spec §3.4.5: "enum(down|up|tap) | held keys auto-repeat host-side".
public enum KeyAction: String, Codable, Sendable, Equatable, CaseIterable {
    case down
    case up
    case tap
}
