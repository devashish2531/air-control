import ArgumentParser
import AirMouseCore

@main
struct AirMouseCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "airmouse-cli",
        abstract: "Speaks the Air Mouse protocol for testing the Mac helper without a phone.",
        subcommands: []
    )
}
