// Commands/Click.swift
// `aircontrol-cli click [--button left|right|middle] [--double]` — sends a `click` message (spec
// §3.4.5): `tap` posts down then up host-side; `--double` sends two taps, `count: 2` on the second.
import AirControlCore
import AirControlProtocol
import ArgumentParser
import Foundation

struct ClickCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click",
        abstract: "Send a mouse click."
    )

    @OptionGroup var hostOptions: HostOptions

    @Option(help: "left, right, or middle.")
    var button: MouseButton = .left

    @Flag(help: "Send a double-click (two taps, count: 1 then 2).")
    var double: Bool = false

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

        try await session.sendClick(AirControlProtocol.Click(button: button, action: .tap, count: 1, modifiers: []))
        if double {
            try await session.sendClick(AirControlProtocol.Click(button: button, action: .tap, count: 2, modifiers: []))
        }
        print("Sent \(double ? "double-" : "")click: \(button.rawValue)")
        await session.close(reason: .userQuit)
    }
}

extension MouseButton: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }
}
