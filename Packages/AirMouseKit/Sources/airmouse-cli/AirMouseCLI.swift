import ArgumentParser
import AirMouseCore

@main
struct AirMouseCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "airmouse-cli",
        abstract: "Speaks the Air Mouse protocol for testing the Mac helper without a phone.",
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

