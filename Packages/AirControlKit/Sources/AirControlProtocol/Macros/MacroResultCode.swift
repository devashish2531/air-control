import Foundation

/// `macroResult.code`. spec §3.4.5: "enum(ok|notFound|blockedByPolicy|confirmationRequired|
/// timeout|failed)".
public enum MacroResultCode: String, Codable, Sendable, Equatable, CaseIterable {
    case ok
    case notFound
    case blockedByPolicy
    case confirmationRequired
    case timeout
    case failed
}
