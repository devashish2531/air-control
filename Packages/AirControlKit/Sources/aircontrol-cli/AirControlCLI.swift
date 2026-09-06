import ArgumentParser
import AirControlCore

@main
struct AirControlCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aircontrol-cli",
        abstract: "Speaks the Air Control protocol for testing the Mac helper without a phone.",
        subcommands: [
            Discover.self,
            Pair.self,
            Connect.self,
            Move.self,
            ClickCommand.self,
            Scroll.self,
            TypeText.self,
            KeyCommand.self,
            Media.self,
            Bench.self,
            Replay.self,
        ]
    )
}

