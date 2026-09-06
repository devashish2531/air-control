// App/ConnectionStatusDot.swift
// docs/08 §2.1 — the app's single connection indicator: a 10 pt dot placed as the top-leading
// toolbar item on every tab (both the iPhone tab view and the iPad split view detail toolbar).
// Replaces `ConnectionPillButton` and its width/offset workarounds entirely. Tap opens the
// Devices sheet. Colours: green = connected, amber (pulsing) = connecting/reconnecting/pairing/
// browsing, grey = disconnected/paused, red = error. An optional short text label appears only
// at iPad regular width (docs/08 §2.1).

import SwiftUI

public struct ConnectionStatusDot: View {
    let environment: AppEnvironment
    @Binding var showDevices: Bool

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isPulsing = false

    public init(environment: AppEnvironment, showDevices: Binding<Bool>) {
        self.environment = environment
        self._showDevices = showDevices
    }

    public var body: some View {
        Button {
            showDevices = true
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
                    .opacity(isAnimated && isPulsing ? 0.35 : 1)
                if horizontalSizeClass == .regular {
                    Text(compactLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .minimumTapTarget()
        .onAppear { updatePulsing() }
        .onChange(of: isAnimated) { _, _ in updatePulsing() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityHint(Text("Opens Devices", comment: "Accessibility hint for the connection status dot"))
        .accessibilityAddTraits(.isButton)
    }

    private func updatePulsing() {
        guard isAnimated, !reduceMotion else {
            isPulsing = false
            return
        }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }

    private var isAnimated: Bool {
        switch environment.connection.connectionState {
        case .browsing, .connecting, .pairing, .reconnecting: return true
        case .idle, .connected, .suspended, .failed: return false
        }
    }

    private var dotColor: Color {
        switch environment.connection.connectionState {
        case .connected: return .green
        case .browsing, .connecting, .pairing, .reconnecting: return .orange
        case .idle, .suspended: return .secondary
        case .failed: return .red
        }
    }

    /// Short on-screen label shown only at iPad regular width (docs/08 §2.1).
    private var compactLabel: String {
        switch environment.connection.connectionState {
        case .idle, .suspended: return String(localized: "Not connected", comment: "Connection status dot compact label")
        case .browsing: return String(localized: "Searching…", comment: "Connection status dot compact label")
        case .connecting: return String(localized: "Connecting…", comment: "Connection status dot compact label")
        case .pairing: return String(localized: "Pairing…", comment: "Connection status dot compact label")
        case .connected(let hostName): return hostName
        case .reconnecting(let hostName): return hostName
        case .failed: return String(localized: "Not connected", comment: "Connection status dot compact label")
        }
    }

    private var accessibilityLabel: String {
        switch environment.connection.connectionState {
        case .connected(let hostName):
            return String(localized: "Connected to \(hostName)", comment: "Connection status dot accessibility label")
        default:
            return String(localized: "Not connected", comment: "Connection status dot accessibility label")
        }
    }

    /// Finer-grained current state so VoiceOver announces state changes even while the coarse
    /// label above stays "Not connected" (docs/08 §2.1).
    private var accessibilityValue: String {
        switch environment.connection.connectionState {
        case .idle: return String(localized: "Idle", comment: "Connection status dot accessibility value")
        case .browsing: return String(localized: "Searching for your Mac", comment: "Connection status dot accessibility value")
        case .connecting: return String(localized: "Connecting", comment: "Connection status dot accessibility value")
        case .pairing: return String(localized: "Pairing", comment: "Connection status dot accessibility value")
        case .connected(let hostName): return String(localized: "Connected to \(hostName)", comment: "Connection status dot accessibility value")
        case .reconnecting(let hostName): return String(localized: "Reconnecting to \(hostName)", comment: "Connection status dot accessibility value")
        case .suspended: return String(localized: "Paused", comment: "Connection status dot accessibility value")
        case .failed: return String(localized: "Connection error", comment: "Connection status dot accessibility value")
        }
    }
}

#Preview {
    ConnectionStatusDot(environment: .preview(), showDevices: .constant(false))
}
