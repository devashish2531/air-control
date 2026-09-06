// Commands/Connect.swift
// `aircontrol-cli connect` — trusted reconnect (spec §3.3.1): `hello { pairing: false }` to a
// previously-paired host, print the negotiated `ConnectedInfo`. `--keep-alive` holds the session,
// sending heartbeats on the negotiated cadence (spec §3.4.6), until Ctrl-C.
import AirControlCore
import AirControlProtocol
import ArgumentParser
import Dispatch
import Foundation

struct Connect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Reconnect to a previously-paired host."
    )

    @OptionGroup var hostOptions: HostOptions

    @Flag(help: "Keep the session open (sending heartbeats) until Ctrl-C.")
    var keepAlive: Bool = false

    @Flag(help: "Print the result as JSON.")
    var json: Bool = false

    func run() async throws {
        let pinnedFingerprint = try CLIRuntime.resolvePinnedFingerprint(hostOptions)
        let (session, control, _) = try await CLIRuntime.openSession(
            host: hostOptions.host,
            controlPort: hostOptions.port,
            pinnedFingerprint: pinnedFingerprint,
            verbose: hostOptions.verbose
        )

        let info: ConnectedInfo
        do {
            info = try await session.connect()
        } catch {
            await control.close()
            throw CLIError("connect failed: \(error)")
        }

        if json {
            let payload: [String: Any] = [
                "host": info.host.name,
                "model": info.host.model,
                "protocolVersion": info.protocolVersion,
                "udpPort": info.udpPort,
                "heartbeatMs": info.heartbeatMs,
                "sessionTimeoutMs": info.sessionTimeoutMs,
                "sessionCount": info.sessionCount,
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            print(String(data: data, encoding: .utf8) ?? "{}")
        } else {
            print("Connected to \(info.host.name) (\(info.host.model)), protocol v\(info.protocolVersion)")
            print("udpPort=\(info.udpPort) heartbeatMs=\(info.heartbeatMs) otherSessions=\(info.sessionCount)")
        }

        if keepAlive {
            print("Holding session — Ctrl-C to quit.")
            let heartbeatNanos = UInt64(max(50, info.heartbeatMs)) * 1_000_000
            signal(SIGINT, SIG_IGN)
            let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
            let loopTask = Task {
                while !Task.isCancelled {
                    try? await session.sendHeartbeat()
                    try? await Task.sleep(nanoseconds: heartbeatNanos)
                }
            }
            sigintSource.setEventHandler { loopTask.cancel() }
            sigintSource.resume()
            await loopTask.value
            sigintSource.cancel()
        }

        await session.close(reason: .userQuit)
    }
}
