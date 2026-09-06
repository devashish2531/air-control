// Security: script macros global opt-in (with warning), pairing window timeout (assignment brief).
// spec §7.5 secure default: "scripts off" — allowScriptsGlobal defaults to false (HostSettings.swift).
import SwiftUI

struct SecuritySettingsTab: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Toggle("Allow script macros (global)", isOn: $settings.allowScriptsGlobal)
            if settings.allowScriptsGlobal {
                Label(
                    "Script macros run AppleScript/shell/Shortcuts you author. Only enable devices you trust — a compromised phone could run arbitrary commands on this Mac.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                .font(.footnote)
            }

            Toggle("Require confirmation for all macros", isOn: $settings.requireConfirmationAll)

            Stepper(
                "Pairing window timeout: \(settings.pairingWindowTimeoutSeconds) s",
                value: $settings.pairingWindowTimeoutSeconds,
                in: 30...300,
                step: 15
            )
        }
    }
}
