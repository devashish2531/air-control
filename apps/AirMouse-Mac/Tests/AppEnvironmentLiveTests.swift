// AppEnvironmentLiveTests — integration task: `AppEnvironment.live(launchArguments:)` must wire every
// service slot to its real implementation instead of a `Placeholder*` (App/AppEnvironment.swift). Runs
// with `--loopback`-flavored launch arguments throughout so it never touches real Wi-Fi/Bonjour or posts
// real CGEvents to whatever window has focus on the machine running the test (same `--loopback`
// contract `IntegrationTests/LoopbackIntegrationTests.swift` documents).
import Testing
@testable import Air_Mouse
import AirMouseProtocol
import Foundation

@MainActor
@Suite struct AppEnvironmentLiveTests {
    @Test func liveConstructsRealNonPlaceholderServices() async {
        let environment = await AppEnvironment.live(launchArguments: LaunchArguments(loopback: true))

        #expect(!(environment.hostService is PlaceholderHostService))
        #expect(!(environment.eventInjector is PlaceholderEventInjector))
        #expect(!(environment.macroStore is PlaceholderMacroStore))
        #expect(!(environment.trustStore is PlaceholderTrustStore))
        #expect(!(environment.diagnosticsSink is PlaceholderDiagnosticsSink))

        #expect(environment.hostService is HostServer)
        #expect(environment.eventInjector is EventInjector)
        #expect(environment.macroStore is MacroStore)
        #expect(environment.trustStore is TrustStore)
        #expect(environment.macroFeature != nil)

        await environment.hostService.stop()
    }

    @Test func loopbackSmokeTestStartsAndPrintsAParseablePairingURL() async throws {
        let environment = await AppEnvironment.live(launchArguments: LaunchArguments(loopback: true))
        await environment.hostService.start()

        let urlString = try await environment.hostService.openPairingWindow()
        let parsed = try PairingURL.parse(urlString)
        #expect(parsed.tcpPort > 0, "loopback HostServer should bind a real (ephemeral) TCP port")
        #expect(!parsed.secret.isEmpty)
        #expect(!parsed.fingerprint.isEmpty)

        await environment.hostService.closePairingWindow()
        await environment.hostService.stop()
    }

    /// `AppEnvironment.preview`/the default initializer must still work standalone (SwiftUI previews,
    /// and any test that wants a cheap, non-networked instance) — this is the counterpart guarding
    /// against `wireLiveServices()` accidentally becoming required.
    @Test func previewStaysPlaceholderBacked() {
        let environment = AppEnvironment.preview
        #expect(environment.hostService is PlaceholderHostService)
        #expect(environment.macroFeature == nil)
    }
}
