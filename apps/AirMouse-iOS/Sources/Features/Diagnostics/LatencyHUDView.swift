// Features/Diagnostics/LatencyHUDView.swift
// Overlay showing RTT p50/p95, probe RTT, one-way estimate, loss %, and channel (arch §8.2),
// gated behind Labs › Latency HUD (spec §4.1.9 Advanced, `am.labs.latencyHUD`). Apply with
// `.latencyHUD(diagnostics:isEnabled:)` from any feature screen that wants the overlay.

import SwiftUI

public struct LatencyHUDView: View {
    let sample: LatencySample?

    public init(sample: LatencySample?) {
        self.sample = sample
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Latency", comment: "Diagnostics HUD title")
                .font(.caption2.weight(.semibold))
            if let sample {
                row(String(localized: "RTT p50", comment: "Diagnostics HUD metric label"), millis: sample.rttMillisP50)
                row(String(localized: "RTT p95", comment: "Diagnostics HUD metric label"), millis: sample.rttMillisP95)
                row(String(localized: "Probe RTT", comment: "Diagnostics HUD metric label"), millis: sample.probeRTTMillis)
                row(String(localized: "One-way est.", comment: "Diagnostics HUD metric label"), millis: sample.oneWayEstimateMillis)
                if let loss = sample.lossPercent {
                    Text("\(String(localized: "Loss", comment: "Diagnostics HUD metric label")): \(loss, specifier: "%.1f")%")
                        .font(.caption2.monospacedDigit())
                }
                Text("\(String(localized: "Channel", comment: "Diagnostics HUD metric label")): \(sample.channel == .udp ? String(localized: "UDP") : String(localized: "TCP fallback"))")
                    .font(.caption2.monospacedDigit())
                Text("\(String(localized: "In flight", comment: "Diagnostics HUD metric label")): \(sample.inFlightDatagrams)")
                    .font(.caption2.monospacedDigit())
            } else {
                Text("No data yet", comment: "Diagnostics HUD placeholder before first sample")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Latency diagnostics", comment: "Accessibility label for the diagnostics HUD"))
    }

    @ViewBuilder
    private func row(_ label: String, millis: Double?) -> some View {
        if let millis {
            Text("\(label): \(millis, specifier: "%.0f") ms")
                .font(.caption2.monospacedDigit())
        }
    }
}

public extension View {
    /// Overlays `LatencyHUDView` top-trailing when `isEnabled` (Labs › Latency HUD).
    func latencyHUD(diagnostics: DiagnosticsModel, isEnabled: Bool) -> some View {
        overlay(alignment: .topTrailing) {
            if isEnabled {
                LatencyHUDView(sample: diagnostics.latest)
                    .padding(8)
            }
        }
    }
}

#Preview {
    LatencyHUDView(sample: LatencySample(rttMillisP50: 8, rttMillisP95: 14, probeRTTMillis: 9, oneWayEstimateMillis: 4, lossPercent: 0.2, channel: .udp, inFlightDatagrams: 1))
        .padding()
}
