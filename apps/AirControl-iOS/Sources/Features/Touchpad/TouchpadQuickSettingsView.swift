// Features/Touchpad/TouchpadQuickSettingsView.swift
// docs/08 §2.1 — content behind the touchpad's compact trailing "quick settings" control
// (`TouchpadModeRibbon`): the pointer-sensitivity slider that used to live inline on the pad
// (long-press reveal, spec §4.1.4) is reached from here instead, plus an elevated-latency note
// when the active channel has fallen back to TCP (spec §9 diagnostics). Connection state itself
// is deliberately not shown here — the toolbar's `ConnectionStatusDot` (App/RootTabView.swift,
// another agent's file, not modified here) is the touchpad's only connection indicator, and this
// sheet must not become a second one.

import SwiftUI

struct TouchpadQuickSettingsView: View {
    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss

    let controller: TouchpadController
    let isElevatedLatency: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "tortoise")
                            .foregroundStyle(.secondary)
                        Slider(
                            value: sensitivityBinding,
                            in: Double(PointerSettings.sensitivityRange.lowerBound)...Double(PointerSettings.sensitivityRange.upperBound),
                            step: 1
                        )
                        Image(systemName: "hare")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(Text("Pointer sensitivity", comment: "Accessibility label for the touchpad quick settings sensitivity slider"))
                } header: {
                    Text("Pointer sensitivity", comment: "Touchpad quick settings sensitivity section header")
                }

                if isElevatedLatency {
                    Section {
                        Label {
                            Text("Elevated latency — the connection has fallen back to a slower channel.", comment: "Touchpad quick settings elevated-latency note")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(Text("Touchpad", comment: "Touchpad quick settings navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", comment: "Touchpad quick settings dismiss button")
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var sensitivityBinding: Binding<Double> {
        Binding(
            get: { Double(environment.userSettings.snapshot.pointer.sensitivity) },
            set: { newValue in
                environment.userSettings.snapshot.pointer.sensitivity = Int(newValue.rounded())
                controller.pushSettingsToHost()
            }
        )
    }
}

#Preview {
    let env = AppEnvironment.preview()
    TouchpadQuickSettingsView(
        controller: TouchpadController(
            userSettings: env.userSettings,
            motion: NoOpMotionEnqueuer(),
            controlSink: NoOpControlMessageSink(),
            haptics: env.haptics
        ),
        isElevatedLatency: true
    )
    .environment(\.appEnvironment, env)
}
