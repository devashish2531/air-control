import Foundation

/// `mediaKey.action`. spec §3.4.5: "enum(tap|down|up)".
public enum MediaKeyAction: String, Codable, Sendable, Equatable, CaseIterable {
    case tap
    case down
    case up
}
