// General: launch at login, pause input, device name shown to phones (assignment brief).
import ServiceManagement
import SwiftUI

struct GeneralSettingsTab: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Toggle("Launch Air Mouse at login", isOn: Binding(
                get: { settings.launchAtLogin },
                set: { newValue in
                    settings.launchAtLogin = newValue
                    if newValue {
                        try? SMAppService.mainApp.register()
                    } else {
                        try? SMAppService.mainApp.unregister()
                    }
                }
            ))

            Toggle("Relaunch automatically if it quits unexpectedly", isOn: $settings.relaunchWatchdog)
                .help("Installs a lightweight LaunchAgent watchdog (spec §5.7.1). Off by default.")

            Toggle("Pause input", isOn: Binding(
                get: { environment.isInputPaused },
                set: { _ in Task { await environment.toggleInputPaused() } }
            ))

            TextField("Name shown to phones", text: $settings.deviceDisplayName)

            Button("Run setup again") {
                settings.setupCompleted = false
            }
        }
    }
}
