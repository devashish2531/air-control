// spec §5.1.1 "LSUIElement = YES agent app; no Dock icon; no main window after onboarding" and §5.1.3
// "Windows". Main actor hosts SwiftUI (arch §3.3); networking/injection/macro executors are owned by
// other agents and reached only through the protocols in ServiceProtocols.swift.
import SwiftUI

@main
struct AirMouseHelperApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        MenuBarExtra {
            MenuBarScene().environment(environment)
        } label: {
            MenuBarIconLabel().environment(environment)
        }
        .menuBarExtraStyle(.menu)

        Window("Air Mouse Setup", id: WindowID.onboarding) {
            OnboardingWindow().environment(environment)
        }
        .windowResizability(.contentSize)

        Window("Settings", id: WindowID.preferences) {
            PreferencesWindow().environment(environment)
        }

        Window("Trusted Devices", id: WindowID.trustedDevices) {
            TrustedDevicesWindow().environment(environment)
        }

        Window("Diagnostics", id: WindowID.diagnostics) {
            DiagnosticsWindow().environment(environment)
        }

        Window("Pair New Device", id: WindowID.pairing) {
            PairingWindow().environment(environment)
        }
        .windowResizability(.contentSize)

        Window("Macros", id: WindowID.macroEditor) {
            MacroEditorWindow().environment(environment)
        }
    }
}
