// Features/Touchpad/TouchpadModeRibbon.swift
// Top-edge overlay (spec §4.1.4): a connection banner (host name + latency dot), "Dragging"
// indicator when drag-lock is active, and "Elevated latency" banner; long-press reveals the 1–10
// sensitivity quick-slider with live preview (sends `settings` immediately on change).
//
// Owner UI request: the toolbar's connection pill (`ConnectionPillButton`, App/RootTabView.swift,
// another agent's file, not modified here) is the single connection-status indicator app-wide —
// this view must never float a second, redundant host-name/dot pill over the pad while
// `connectionState == .connected`. So the connection banner below only renders for the
// non-connected states (browsing/connecting/pairing/reconnecting/suspended/failed/idle), matching
// spec §4.1.4's "Paused on Mac" / error-banner language; while connected it disappears entirely.
// The "Dragging" and "Elevated latency" badges are independent of connection state and can still
// appear while connected. A small always-present quick-settings affordance (not a pill — a plain
// circular icon button, carrying no connection-status text) keeps the sensitivity slider (spec
// §4.1.4, kept per owner item 5) reachable via long-press even when the banner is hidden.
//
// The whole row is leading/trailing-anchored (`Spacer()` between banner content and the
// quick-settings icon, `.frame(maxWidth: .infinity, alignment: .leading)`), never centered over
// the pad — owner item 5: "move any overlays off the pad centre to the top edge of the pad".

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
            topRow
            if showSensitivitySlider {
                sensitivitySlider
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var topRow: some View {
        if hasBannerContent {
            HStack(spacing: 8) {
                if showConnectionBanner {
                    Circle()
                        .fill(latencyDotColor)
                        .frame(width: 8, height: 8)
                    SwiftUI.Text(hostLabel)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
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
                Spacer(minLength: 8)
                quickSettingsButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(bannerAccessibilityLabel)
        } else {
            HStack {
                Spacer()
                quickSettingsButton
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var quickSettingsButton: some View {
        Image(systemName: "slider.horizontal.3")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
            .background(Circle().fill(.ultraThinMaterial))
            .contentShape(Circle())
            .minimumTapTarget()
            .onLongPressGesture {
                withAnimation { showSensitivitySlider.toggle() }
            }
            .accessibilityLabel(SwiftUI.Text("Pointer sensitivity", comment: "Accessibility label for the touchpad sensitivity slider"))
            .accessibilityHint(SwiftUI.Text("Long press to adjust sensitivity", comment: "Accessibility hint for the touchpad mode ribbon"))
            .accessibilityAddTraits(.isButton)
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

    private var hasBannerContent: Bool {
        showConnectionBanner || controller.isDragLockEngaged || isElevatedLatency
    }

    /// Owner UI request: the banner is shown only for non-connected states — the toolbar
    /// connection pill already covers `connected` (see this file's header note).
    private var showConnectionBanner: Bool {
        if case .connected = environment.connection.connectionState { return false }
        return true
    }

    private var bannerAccessibilityLabel: SwiftUI.Text {
        SwiftUI.Text("\(hostLabel), \(controller.isDragLockEngaged ? "dragging" : "idle")", comment: "Accessibility label for the touchpad mode ribbon")
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
