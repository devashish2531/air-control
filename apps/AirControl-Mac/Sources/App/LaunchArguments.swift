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
    /// Dev convenience: forces `Features/Onboarding/OnboardingWindow.swift`'s "Air Control Setup" window
    /// open at launch regardless of Accessibility-trust/`setupCompleted` state (`MenuBarIconLabel`'s
    /// launch-once task), so a rebuilt/re-signed helper whose Accessibility grant already carried over
    /// can still be steered back to onboarding for review/screenshots without `tccutil reset`.
    public var showOnboarding: Bool
    /// Dev flag: after the server starts, open a pairing window and print `AIRCONTROL_PAIR_URL=<url>` to
    /// stdout (normal networking, unlike `--loopback`). Lets on-device tests pair without scanning.
    public var printPairURL: Bool
    /// Dev convenience: overrides the non-loopback TCP/UDP bind ports (`HostFeature.make`'s
    /// `ProtocolConstants.defaultTCPPort`/`defaultUDPPort` otherwise). Lets a second, throwaway copy of
    /// the helper (e.g. for verifying a Keychain-identity fix) run alongside the real one on the
    /// default port without a bind conflict — `--loopback` isn't a substitute for that since it uses
    /// an ephemeral, never-persisted identity.
    public var tcpPort: UInt16?
    public var udpPort: UInt16?

    public init(
        loopback: Bool = false,
        bench: Bool = false,
        logLevel: LogLevel? = nil,
        showOnboarding: Bool = false,
        printPairURL: Bool = false,
        tcpPort: UInt16? = nil,
        udpPort: UInt16? = nil
    ) {
        self.loopback = loopback
        self.printPairURL = printPairURL
        self.bench = bench
        self.logLevel = logLevel
        self.showOnboarding = showOnboarding
        self.tcpPort = tcpPort
        self.udpPort = udpPort
    }

    /// Parses `arguments` (default: the process's own, minus the executable path). Recognizes `--loopback`,
    /// `--bench`, `--show-onboarding` as bare flags and `--log-level <level>` / `--log-level=<level>` with a
    /// `LogLevel` raw value. Anything else is ignored, not rejected, since other agents own additional flags.
    public static func parse(_ arguments: [String] = Array(CommandLine.arguments.dropFirst())) -> LaunchArguments {
        var loopback = false
        var bench = false
        var logLevel: LogLevel?
        var showOnboarding = false
        var printPairURL = false
        var tcpPort: UInt16?
        var udpPort: UInt16?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--loopback":
                loopback = true
            case "--bench":
                bench = true
            case "--show-onboarding":
                showOnboarding = true
            case "--print-pair-url":
                printPairURL = true
            case "--log-level":
                if index + 1 < arguments.count, let level = LogLevel(rawValue: arguments[index + 1]) {
                    logLevel = level
                    index += 1
                }
            case "--tcp-port":
                if index + 1 < arguments.count, let port = UInt16(arguments[index + 1]) {
                    tcpPort = port
                    index += 1
                }
            case "--udp-port":
                if index + 1 < arguments.count, let port = UInt16(arguments[index + 1]) {
                    udpPort = port
                    index += 1
                }
            default:
                if argument.hasPrefix("--log-level="), let level = LogLevel(rawValue: String(argument.dropFirst("--log-level=".count))) {
                    logLevel = level
                }
            }
            index += 1
        }

        return LaunchArguments(
            loopback: loopback,
            bench: bench,
            logLevel: logLevel,
            showOnboarding: showOnboarding,
            printPairURL: printPairURL,
            tcpPort: tcpPort,
            udpPort: udpPort
        )
    }
}
