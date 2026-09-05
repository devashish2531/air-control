// arch §8 "Compile-time flags are avoided; the helper's --loopback, --bench, --port, --identity,
// --pairing-secret, --log-level are runtime arguments parsed in LaunchArguments.swift". This module only
// owns --loopback, --bench, --log-level (the rest belong to the networking/pairing agents); unknown flags
// are ignored rather than rejected so those agents can add their own without touching this file.
import Foundation

public struct LaunchArguments: Sendable, Equatable {
    /// Runs against a loopback/localhost transport instead of real Wi-Fi discovery (owned by the
    /// networking agent; this module only surfaces the flag).
    public var loopback: Bool
    /// Enables bench/performance instrumentation paths.
    public var bench: Bool
    /// Overrides `am.helper.logLevel` for this run only.
    public var logLevel: LogLevel?

    public init(loopback: Bool = false, bench: Bool = false, logLevel: LogLevel? = nil) {
        self.loopback = loopback
        self.bench = bench
        self.logLevel = logLevel
    }

    /// Parses `arguments` (default: the process's own, minus the executable path). Recognizes `--loopback`,
    /// `--bench` as bare flags and `--log-level <level>` / `--log-level=<level>` with a `LogLevel` raw
    /// value. Anything else is ignored, not rejected, since other agents own additional flags.
    public static func parse(_ arguments: [String] = Array(CommandLine.arguments.dropFirst())) -> LaunchArguments {
        var loopback = false
        var bench = false
        var logLevel: LogLevel?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--loopback":
                loopback = true
            case "--bench":
                bench = true
            case "--log-level":
                if index + 1 < arguments.count, let level = LogLevel(rawValue: arguments[index + 1]) {
                    logLevel = level
                    index += 1
                }
            default:
                if argument.hasPrefix("--log-level="), let level = LogLevel(rawValue: String(argument.dropFirst("--log-level=".count))) {
                    logLevel = level
                }
            }
            index += 1
        }

        return LaunchArguments(loopback: loopback, bench: bench, logLevel: logLevel)
    }
}
