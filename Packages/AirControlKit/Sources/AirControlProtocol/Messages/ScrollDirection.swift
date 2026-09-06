import Foundation

/// `settings.scrollDirection`. spec §3.4.5: "enum(host|natural|inverted) | default `host`".
public enum ScrollDirection: String, Codable, Sendable, Equatable, CaseIterable {
    case host
    case natural
    case inverted
}
