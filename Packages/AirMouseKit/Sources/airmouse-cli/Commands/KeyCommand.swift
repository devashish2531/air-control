// Commands/KeyCommand.swift
// `airmouse-cli key <name> [--cmd --shift --opt --ctrl]` — sends one `key` message (spec §3.4.5),
// looking `<name>` up in `KeyNameTable` (e.g. "a", "return", "f5").
import AirMouseCore
import AirMouseProtocol
import ArgumentParser
import Foundation

struct KeyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "key",
        abstract: "Send one keyboard key (tap). See --list for known names."
    )

    @OptionGroup var hostOptions: HostOptions

    @Argument(help: "Key name, e.g. 'a', 'return', 'f5'. Use --list to print every known name.")
    var name: String?

    @Flag(help: "List every recognized key name and exit.")
    var list: Bool = false

    @Flag(name: .customLong("cmd"), help: "Hold ⌘.")
    var cmd: Bool = false
    @Flag(name: .customLong("shift"), help: "Hold ⇧.")
    var shift: Bool = false
    @Flag(name: .customLong("opt"), help: "Hold ⌥.")
    var opt: Bool = false
    @Flag(name: .customLong("ctrl"), help: "Hold ⌃.")
    var ctrl: Bool = false

    func run() async throws {
        if list {
            print(KeyNameTable.allNames.joined(separator: "\n"))
            return
        }
        guard let name else {
            throw CLIError("a key name is required (or pass --list)")
        }
        guard let (code, char) = KeyNameTable.lookup(name) else {
            throw CLIError("unknown key name '\(name)' — try --list")
        }

        var modifiers: KeyModifiers = []
        if cmd { modifiers.insert(.command) }
        if shift { modifiers.insert(.shift) }
        if opt { modifiers.insert(.option) }
        if ctrl { modifiers.insert(.control) }

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

        try await session.sendKey(Key(code: Int(code), char: char, action: .tap, modifiers: modifiers))
        print("Sent key '\(name)' (code \(code))")
        await session.close(reason: .userQuit)
    }
}
