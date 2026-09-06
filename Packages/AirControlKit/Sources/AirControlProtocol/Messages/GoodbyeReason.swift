import Foundation

/// `goodbye.reason`. spec §3.4.5: "enum(userQuit|background|revoked|replaced|hostQuit|sleep|error)".
public enum GoodbyeReason: String, Codable, Sendable, Equatable, CaseIterable {
    case userQuit
    case background
    case revoked
    case replaced
    case hostQuit
    case sleep
    case error
}
