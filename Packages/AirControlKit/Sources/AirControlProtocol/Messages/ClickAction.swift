import Foundation

/// `click.action`. spec §3.4.5: "enum(down|up|tap) | `tap` = host posts down, waits ≥ 15 ms,
/// posts up".
public enum ClickAction: String, Codable, Sendable, Equatable, CaseIterable {
    case down
    case up
    case tap
}
