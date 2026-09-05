// spec §5.1.3 "Diagnostics" window: per-session stats table, inject p50/p95, log level, export.
import SwiftUI

struct DiagnosticsWindow: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: DiagnosticsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                DiagnosticsContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .onAppear {
            if viewModel == nil {
                viewModel = DiagnosticsViewModel(sink: environment.diagnosticsSink)
            }
        }
        .environment(environment)
    }
}

private struct DiagnosticsContent: View {
    @Bindable var viewModel: DiagnosticsViewModel
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = environment.settings
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Injected events/sec: \(viewModel.snapshot.injectedEventsPerSecond, specifier: "%.1f")")
                Spacer()
                Text("inject p50: \(viewModel.snapshot.injectP50Millis, specifier: "%.1f") ms · p95: \(viewModel.snapshot.injectP95Millis, specifier: "%.1f") ms")
            }
            .font(.callout.monospacedDigit())

            List {
                ForEach(viewModel.snapshot.sessions) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.deviceName).bold()
                        Text("motion \(session.motionDatagramRateHz, specifier: "%.0f") Hz · RTT p50 \(session.rttP50Millis, specifier: "%.0f") ms / p95 \(session.rttP95Millis, specifier: "%.0f") ms")
                        Text("dropped \(session.droppedCount) · replayed \(session.replayedCount) · stale \(session.staleCount) · AEAD failures \(session.aeadFailureCount)")
                        Text("cipher \(session.negotiatedCipher) · peer \(session.peerFingerprintPrefix) · channel \(session.channel)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption.monospacedDigit())
                }
            }
            if viewModel.snapshot.sessions.isEmpty {
                Text("No active sessions.")
                    .foregroundStyle(.secondary)
            }

            // spec §9 diagnostics deliverable: recent accept/TLS/pairing/disconnect activity,
            // visible without opening Console.app.
            if !viewModel.snapshot.recentEvents.isEmpty {
                Text("Recent connection events").font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(viewModel.snapshot.recentEvents.enumerated()), id: \.offset) { _, event in
                            Text(event)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption.monospaced())
                .frame(maxHeight: 120)
            }

            HStack {
                Picker("Log level", selection: $settings.logLevel) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue.capitalized).tag(level)
                    }
                }
                .frame(width: 220)
                Spacer()
                Button("Copy Diagnostics Report") {
                    viewModel.copyDiagnosticsReport()
                }
            }
        }
        .padding()
        .task {
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }
}
