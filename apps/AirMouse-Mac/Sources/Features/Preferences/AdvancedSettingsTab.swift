// Advanced: log level, ports display (assignment brief); Labs is arch §8's Advanced-only, default-off item.
import SwiftUI

struct AdvancedSettingsTab: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Picker("Log level", selection: $settings.logLevel) {
                ForEach(LogLevel.allCases, id: \.self) { level in
                    Text(level.rawValue.capitalized).tag(level)
                }
            }

            LabeledContent("TCP port", value: "\(settings.tcpPort)")
            LabeledContent("UDP port", value: "\(settings.udpPort)")

            Toggle("Labs: motion prediction", isOn: $settings.labsPrediction)
        }
    }
}
