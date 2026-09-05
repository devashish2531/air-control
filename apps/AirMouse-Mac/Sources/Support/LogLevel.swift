// spec §5.7.3, §6.2 (am.helper.logLevel) — runtime log verbosity shared by Logging, HostSettings and LaunchArguments.
import Foundation

/// Ordered verbosity level for the helper's `os.Logger` output. `.debug` is off in release builds (spec §5.7.3).
public enum LogLevel: String, CaseIterable, Codable, Sendable, Comparable {
    case debug
    case info
    case warning
    case error

    /// spec §6.2 default for `am.helper.logLevel`.
    public static let `default`: LogLevel = .info

    private var rank: Int {
        switch self {
        case .debug: 0
        case .info: 1
        case .warning: 2
        case .error: 3
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rank < rhs.rank }
}
