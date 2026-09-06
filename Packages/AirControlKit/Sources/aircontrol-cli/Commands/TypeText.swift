// Commands/TypeText.swift
// `aircontrol-cli type "<text>"` — sends a `text` message (spec §3.4.5: 1–16384 bytes UTF-8, grapheme
// clusters never split across messages — a single `Text` message here is always one grapheme-safe
// String, so this command never needs to split it itself).
import AirControlCore
import AirControlProtocol
import ArgumentParser
import Foundation

struct TypeText: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "type",
        abstract: "Type a string of Unicode text."
    )

    @OptionGroup var hostOptions: HostOptions

    @Argument(help: "The text to type.")
    var text: String

    @Flag(help: "Mark as secure (host disables its own debug echo; no other wire effect).")
    var secure: Bool = false

    func run() async throws {
        guard text.utf8.count >= 1, text.utf8.count <= ProtocolConstants.textMessageMaxBytes else {
            throw CLIError("text must be 1–\(ProtocolConstants.textMessageMaxBytes) UTF-8 bytes")
        }
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

        try await session.sendText(Text(s: text, secure: secure))
        print("Sent \(text.utf8.count) bytes of text.")
        await session.close(reason: .userQuit)
    }
}
