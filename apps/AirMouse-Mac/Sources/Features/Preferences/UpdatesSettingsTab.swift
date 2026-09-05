// Updates: opt-in check toggle, interval (assignment brief). spec §5.7.2: opt-in, default off.
// TODO(M8): Sparkle — see Services/UpdateService/UpdateService.swift.
import SwiftUI

struct UpdatesSettingsTab: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            if environment.installSource == .homebrewCask {
                Text("Installed via Homebrew — update with `brew upgrade --cask air-mouse`.")
                    .foregroundStyle(.secondary)
            } else {
                Toggle("Check for updates automatically", isOn: $settings.updateCheckOptIn)
                Stepper(
                    "Check every \(settings.updateCheckIntervalHours) hours",
                    value: $settings.updateCheckIntervalHours,
                    in: 1...168,
                    step: 1
                )
                .disabled(!settings.updateCheckOptIn)
            }
        }
    }
}
