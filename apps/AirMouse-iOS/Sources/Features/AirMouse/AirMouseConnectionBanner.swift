// Features/AirMouse/AirMouseConnectionBanner.swift
// A small status banner for the Air Mouse tab mirroring the intent of the Touchpad mode ribbon's
// connection banners (spec §4.1.4) — this tab has no ribbon of its own (§4.1.5's layout is status
// card / click area / clutch), so this sits above the status card whenever not connected.
import SwiftUI

struct AirMouseConnectionBanner: View {
    let connectionState: ConnectionState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: glyph)
            SwiftUI.Text(message)
                .font(.footnote.weight(.medium))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .foregroundStyle(tint)
        .accessibilityElement(children: .combine)
    }

    private var message: LocalizedStringKey {
        switch connectionState {
        case .idle: return "Not connected — motion won't reach your Mac"
        case .browsing: return "Searching for your Mac…"
        case .connecting: return "Connecting…"
        case .pairing: return "Pairing…"
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting…"
        case .suspended: return "Connection paused"
        case .failed: return "Not connected — motion won't reach your Mac"
        }
    }

    private var glyph: String {
        switch connectionState {
        case .connected: return "checkmark.circle.fill"
        case .connecting, .pairing, .reconnecting, .browsing: return "arrow.triangle.2.circlepath"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch connectionState {
        case .connected: return .green
        case .connecting, .pairing, .reconnecting, .browsing: return .orange
        default: return .secondary
        }
    }
}
