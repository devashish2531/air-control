import Foundation

/// `settings.acceleration`. spec §3.4.5: "enum(off|precise|default|fast) | default `default`".
public enum Acceleration: String, Codable, Sendable, Equatable, CaseIterable {
    case off
    case precise
    case `default`
    case fast
}
