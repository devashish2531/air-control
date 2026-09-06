import Testing
@testable import Air_Control
import Foundation

@MainActor
@Suite struct HostSettingsTests {
    private func makeSettings() -> HostSettings {
        let suiteName = "com.aircontrol.helper.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return HostSettings(defaults: defaults)
    }

    @Test func defaultsMatchArchitectureTable() {
        let settings = makeSettings()
        #expect(settings.setupCompleted == false)
        #expect(settings.launchAtLogin == true)
        #expect(settings.relaunchWatchdog == false)
        #expect(settings.allowScriptsGlobal == false)
        #expect(settings.requireConfirmationAll == false)
        #expect(settings.naturalScrollOverride == .system)
        #expect(settings.pairingWindowTimeoutSeconds == 60)
        #expect(settings.updateCheckOptIn == false)
        #expect(settings.logLevel == .info)
        #expect(settings.tcpPort == 47800)
        #expect(settings.udpPort == 47800)
        #expect(settings.labsPrediction == false)
    }

    @Test func writesPersistThroughTheBackingDefaults() {
        let settings = makeSettings()
        settings.allowScriptsGlobal = true
        settings.logLevel = .debug
        settings.naturalScrollOverride = .inverted
        settings.tcpPort = 51000

        #expect(settings.allowScriptsGlobal == true)
        #expect(settings.logLevel == .debug)
        #expect(settings.naturalScrollOverride == .inverted)
        #expect(settings.tcpPort == 51000)
    }
}
