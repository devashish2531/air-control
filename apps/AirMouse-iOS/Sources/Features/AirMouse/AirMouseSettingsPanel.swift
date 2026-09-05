// Features/AirMouse/AirMouseSettingsPanel.swift
// Inline quick-settings for the Air Mouse tab: sensitivity + smoothing sliders (spec §4.1.9,
// live), clutch mode, recenter mode, lock orientation, and "Recalibrate now" (spec §4.3.7).
//
// spec §4.1.9 lists these as *Settings › Gyro* rows, owned by the (separately-assigned) Settings
// screen. `UserSettings.GyroSettings` only models sensitivity/smoothing/dead-zone (see the
// deviation note in `GyroEngine.swift`), so clutch/recenter/lock-orientation have nowhere to live
// in that screen yet; surfacing them here too keeps the tab fully usable standalone. Once the
// Settings screen models the missing fields against the same `AirMouseLocalSettings` store (or a
// widened `GyroSettings`), this panel can be trimmed to just the two sliders.
import AirMouseFilters
import SwiftUI

struct AirMouseSettingsPanel: View {
    @Bindable var viewModel: AirMouseViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            slider(
                title: "Sensitivity",
                value: $viewModel.sensitivity,
                range: 1...10,
                valueLabel: { "\(Int($0))" }
            )
            slider(
                title: "Smoothing",
                value: $viewModel.smoothing,
                range: 0...10,
                valueLabel: { "\(Int($0))" }
            )
            slider(
                title: "Dead zone",
                value: $viewModel.deadZone,
                range: 0...3,
                valueLabel: { String(format: "%.1f°/s", $0) }
            )

            Picker("Clutch", selection: clutchModeBinding) {
                SwiftUI.Text("Hold").tag(ClutchMode.hold)
                SwiftUI.Text("Toggle").tag(ClutchMode.toggle)
            }
            .pickerStyle(.segmented)

            Picker("Recenter", selection: recenterModeBinding) {
                SwiftUI.Text("Double-tap").tag(GyroRecenterMode.doubleTap)
                SwiftUI.Text("Shake").tag(GyroRecenterMode.shake)
                SwiftUI.Text("Both").tag(GyroRecenterMode.both)
            }
            .pickerStyle(.segmented)

            Toggle("Lock orientation", isOn: lockOrientationBinding)

            Button {
                viewModel.recalibrateNow()
            } label: {
                Label("Recalibrate now", systemImage: "arrow.clockwise.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .minimumTapTarget()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .airMouseDynamicTypeRange()
    }

    private func slider(
        title: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueLabel: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SwiftUI.Text(title)
                    .font(.subheadline)
                Spacer()
                SwiftUI.Text(valueLabel(value.wrappedValue))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .accessibilityLabel(SwiftUI.Text(title))
                .accessibilityValue(SwiftUI.Text(valueLabel(value.wrappedValue)))
        }
    }

    private var clutchModeBinding: Binding<ClutchMode> {
        Binding(
            get: { viewModel.engine.clutchMode },
            set: { viewModel.setClutchMode($0) }
        )
    }

    private var recenterModeBinding: Binding<GyroRecenterMode> {
        Binding(
            get: { viewModel.engine.recenterMode },
            set: { viewModel.setRecenterMode($0) }
        )
    }

    private var lockOrientationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.localSettings.isOrientationLocked },
            set: { viewModel.setOrientationLocked($0) }
        )
    }
}
