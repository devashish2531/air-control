// Pointer: host acceleration/sensitivity defaults, natural-scroll inherit (assignment brief).
import SwiftUI

struct PointerSettingsTab: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Slider(value: $settings.pointerAccelerationDefault, in: 0...2) {
                Text("Acceleration")
            }
            Slider(value: $settings.pointerSensitivityDefault, in: 0...2) {
                Text("Sensitivity")
            }
            Picker("Natural scroll", selection: $settings.naturalScrollOverride) {
                Text("Follow system").tag(HostSettings.NaturalScrollOverride.system)
                Text("Natural").tag(HostSettings.NaturalScrollOverride.natural)
                Text("Inverted").tag(HostSettings.NaturalScrollOverride.inverted)
            }
            .pickerStyle(.radioGroup)
        }
    }
}
