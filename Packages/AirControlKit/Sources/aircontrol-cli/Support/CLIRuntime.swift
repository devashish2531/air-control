// Support/CLIRuntime.swift
// Shared plumbing every subcommand that talks to a host needs: resolving `--host`/`--port`/
// `--fingerprint` into a pinned target, loading/creating the persisted CLI identity (`CLIStore`), and
// opening a `ClientSession` over `CLIControlChannel`/`CLIDatagramChannel`.
import AirControlCore
import AirControlCrypto
import AirControlProtocol
import ArgumentParser
import Foundation

/// A clear, non-zero-exit-code error every subcommand throws instead of a raw system error.
struct CLIError: Error, CustomStringConvertible {
    var message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// Shared `--host`/`--port`/`--fingerprint` options for any subcommand that connects to a host.
struct HostOptions: ParsableArguments {
    @Option(help: "Host IPv4/IPv6 literal or hostname.")
    var host: String

    @Option(help: "Control (TCP) port.")
    var port: Int = ProtocolConstants.defaultTCPPort

    @Option(help: "Override the pinned host certificate fingerprint (64 hex chars) instead of the saved trust record.")
    var fingerprint: String?

    @Flag(help: "Log verbose diagnostic output to stderr.")
    var verbose: Bool = false

    init() {}
}

/// Writes one diagnostic line to stderr iff `--verbose` was passed.
func verboseLog(_ message: @autoclosure () -> String, enabled: Bool) {
    guard enabled else { return }
    FileHandle.standardError.write(("[aircontrol-cli] " + message() + "\n").data(using: .utf8)!)
}

enum CLIRuntime {
    /// Resolves the fingerprint to pin for `options.host`: an explicit `--fingerprint` override, else
    /// the saved trust record from a prior `pair` (spec §3.2.4 / §3.3.1 trusted reconnect).
    static func resolvePinnedFingerprint(_ options: HostOptions) throws -> Fingerprint {
        if let hex = options.fingerprint {
            guard let fingerprint = Fingerprint(hexString: hex) else {
                throw CLIError("--fingerprint must be 64 hex characters")
            }
            return fingerprint
        }
        guard let record = CLIStore.findTrustedHost(matching: options.host),
              let fingerprint = Fingerprint(hexString: record.fingerprintHex)
        else {
            throw CLIError("no saved trust record for '\(options.host)' — run 'pair <url>' first, or pass --fingerprint")
        }
        return fingerprint
    }

    /// `hello.device` this build of the CLI reports (spec §3.4.5).
    static func device() -> Hello.Device {
        Hello.Device(
            name: ProcessInfo.processInfo.hostName,
            model: "aircontrol-cli",
            os: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            app: "aircontrol-cli/1.0"
        )
    }

    /// Loads/creates the persisted CLI identity and opens a TLS control connection pinned to
    /// `pinnedFingerprint`, plus the `ClientSession` driving it. Caller is responsible for `connect`/
    /// `pair` and eventual `close()`.
    static func openSession(
        host: String,
        controlPort: Int,
        pinnedFingerprint: Fingerprint,
        displayHz: Int = 60,
        verbose: Bool = false
    ) async throws -> (session: ClientSession, control: CLIControlChannel, localFingerprint: Fingerprint) {
        let identity = try CLIStore.loadOrCreateIdentity()
        verboseLog("client identity fingerprint \(identity.fingerprint.shortLogPrefix)…", enabled: verbose)
        verboseLog("connecting to \(host):\(controlPort), pinning \(pinnedFingerprint.shortLogPrefix)…", enabled: verbose)
        let control: CLIControlChannel
        do {
            control = try await CLIControlChannel.connect(
                host: host,
                port: controlPort,
                identity: identity.secIdentity,
                pinnedFingerprint: pinnedFingerprint
            )
        } catch {
            throw CLIError("could not connect to \(host):\(controlPort) — \(error)")
        }
        verboseLog("TLS control connection ready", enabled: verbose)
        let session = ClientSession(
            control: control,
            datagramProvider: { udpPort in try await CLIDatagramChannel.connect(host: host, port: udpPort) },
            clock: SystemClock(),
            localFingerprint: identity.fingerprint,
            device: device(),
            displayHz: displayHz
        )
        return (session, control, identity.fingerprint)
    }

    /// Monotonic microseconds for `MotionPayload.timestamp` (spec §3.5.2: client monotonic clock).
    static func nowMicros(_ clock: SystemClock = SystemClock()) -> UInt32 {
        UInt32(truncatingIfNeeded: Int64(clock.now() * 1_000_000))
    }
}
