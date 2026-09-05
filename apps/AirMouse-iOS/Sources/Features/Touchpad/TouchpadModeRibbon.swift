// Features/Touchpad/TouchpadModeRibbon.swift
// Mode ribbon (spec §4.1.4): host name, latency dot, "Dragging" indicator when drag-lock is
// active, "Elevated latency" banner; long-press reveals the 1–10 sensitivity quick-slider with
// live preview (sends `settings` immediately on change).

import SwiftUI

public struct TouchpadModeRibbon: View {
    @Environment(\.appEnvironment) private var environment
    let controller: TouchpadController

    @State private var showSensitivitySlider = false

    public init(controller: TouchpadController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(latencyDotColor)
                    .frame(width: 8, height: 8)
                SwiftUI.Text(hostLabel)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if controller.isDragLockEngaged {
                    Label {
                        SwiftUI.Text("Dragging", comment: "Touchpad mode ribbon drag-lock indicator")
                    } icon: {
                        Image(systemName: "hand.draw")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .accessibilityAddTraits(.isSelected)
                }
                if isElevatedLatency {
                    SwiftUI.Text("Elevated latency", comment: "Touchpad mode ribbon banner")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .onLongPressGesture {
                withAnimation { showSensitivitySlider.toggle() }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(SwiftUI.Text("\(hostLabel), \(controller.isDragLockEngaged ? "dragging" : "idle")", comment: "Accessibility label for the touchpad mode ribbon"))
            .accessibilityHint(SwiftUI.Text("Long press to adjust sensitivity", comment: "Accessibility hint for the touchpad mode ribbon"))

            if showSensitivitySlider {
                sensitivitySlider
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .minimumTapTarget()
    }

    private var sensitivitySlider: some View {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel(SwiftUI.Text("Pointer sensitivity", comment: "Accessibility label for the touchpad sensitivity slider"))
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

    private var hostLabel: String {
        switch environment.connection.connectionState {
        case .connected(let hostName): return hostName
        case .reconnecting(let hostName): return String(localized: "Reconnecting to \(hostName)…", comment: "Touchpad ribbon connection state")
        case .connecting: return String(localized: "Connecting…", comment: "Touchpad ribbon connection state")
        case .pairing: return String(localized: "Pairing…", comment: "Touchpad ribbon connection state")
        case .browsing: return String(localized: "Searching…", comment: "Touchpad ribbon connection state")
        case .suspended: return String(localized: "Paused on Mac", comment: "Touchpad ribbon connection state")
        case .idle, .failed: return String(localized: "Not connected", comment: "Touchpad ribbon connection state")
        }
    }

    private var latencyDotColor: Color {
        switch environment.connection.connectionState {
        case .connected: return isElevatedLatency ? .orange : .green
        case .connecting, .pairing, .reconnecting, .browsing: return .yellow
        case .idle, .suspended, .failed: return .secondary
        }
    }

    private var isElevatedLatency: Bool {
        environment.diagnostics.latest?.channel == .tcpFallback
    }
}
