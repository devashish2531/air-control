// Commands/Media.swift
// `airmouse-cli media <play|next|prev|volup|voldown|mute>` — sends one `mediaKey` message
// (spec §3.4.5/§5.3.7).
import AirMouseCore
import AirMouseProtocol
import ArgumentParser
import Foundation

enum MediaKeyName: String, ExpressibleByArgument, CaseIterable {
    case play, next, prev, volup, voldown, mute

    var mediaKey: MediaKey {
        switch self {
        case .play: return .playPause
        case .next: return .next
        case .prev: return .previous
        case .volup: return .volumeUp
        case .voldown: return .volumeDown
        case .mute: return .mute
        }
    }
}

struct Media: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Send a media key (play, next, prev, volup, voldown, mute)."
    )

    @OptionGroup var hostOptions: HostOptions

    @Argument(help: "One of: \(MediaKeyName.allCases.map(\.rawValue).joined(separator: ", ")).")
    var key: MediaKeyName

    func run() async throws {
        let pinnedFingerprint = try CLIRuntime.resolvePinnedFingerprint(hostOptions)
        let (session, control, _) = try await CLIRuntime.openSession(
            host: hostOptions.host,
            controlPort: hostOptions.port,
            pinnedFingerprint: pinnedFingerprint,
            verbose: hostOptions.verbose
        )
        do {
            _ = try await session.connect()
        } catch {
            await control.close()
            throw CLIError("connect failed: \(error)")
        }

        try await session.sendMediaKey(MediaKeyMessage(key: key.mediaKey, action: .tap))
        print("Sent media key: \(key.rawValue)")
        await session.close(reason: .userQuit)
    }
}
