import Foundation

/// `scrollPhase.phase`. spec §3.4.5: "enum(began|ended|cancel)".
public enum ScrollPhaseKind: String, Codable, Sendable, Equatable, CaseIterable {
    case began
    case ended
    case cancel
}
