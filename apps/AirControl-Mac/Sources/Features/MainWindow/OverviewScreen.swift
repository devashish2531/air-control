// docs/08 §5.2 sidebar item 1 "Overview" — status card (server Running/Stopped + TCP/UDP ports,
// Accessibility permission state + "Open System Settings", Local Network note, connected device
// summary), pairing card (Pair New Device shows the QR inline via the existing `PairingContentView`,
// Copy pairing link), and a "Recent activity" list from the Diagnostics ring buffer (last 10).
//
// Deviation: the spec's connected-device line asks for "(name, transport UDP/TCP fallback, RTT,
// since)". `HostServing.connectedSessions` (`App/ServiceProtocols.swift`) has no "connected since"
// timestamp and no transport field — both would need a networking-agent change out of this module's
// file scope (`Services/HostServer`, `Services/SessionManager`). Transport and RTT are recovered by
// cross-referencing `DiagnosticsSink`'s per-session `channel`/`rttP50Millis` (same session `id`);
// "since" is omitted. Noted in this module's report.
import AppKit
import SwiftUI

struct OverviewScreen: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(MainWindowRouter.self) private var router

    @State private var isRunning = false
    @State private var tcpPort: UInt16?
    @State private var udpPort: UInt16?
    @State private var statusPollTask: Task<Void, Never>?

    @State private var diagnosticsViewModel: DiagnosticsViewModel?

    @State private var isPairingActive = false
    @State private var lastPairingURLString: String?
    @State private var didCopyPairingLink = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statusCard
                pairingCard
                recentActivityCard
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Overview")
        .task { await pollServerStatus() }
        .task { startDiagnosticsPolling() }
        .onDisappear {
            statusPollTask?.cancel()
            statusPollTask = nil
            diagnosticsViewModel?.stopPolling()
        }
        .onChange(of: router.pairingRequestToken) { _, _ in
            isPairingActive = true
        }
    }

    // MARK: - Status card

    private var statusCard: some View {
        Card(title: "Status") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(isRunning ? "Running" : "Stopped", systemImage: isRunning ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(isRunning ? .green : .red)
                    if isRunning, let tcpPort {
                        Text("TCP \(tcpPort)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if isRunning, let udpPort {
                        Text("UDP \(udpPort)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack {
                    Label(
                        environment.permissions.isAccessibilityTrusted ? "Accessibility granted" : "Accessibility needed",
                        systemImage: "accessibility"
                    )
                    .foregroundStyle(environment.permissions.isAccessibilityTrusted ? Color.primary : Color.orange)
                    if !environment.permissions.isAccessibilityTrusted {
                        Button("Open System Settings") {
                            environment.permissions.openSystemSettingsAccessibility()
                        }
                    }
                    Spacer()
                }

                Text("Air Control uses your local network to find and connect to your iPhone or iPad. Nothing is sent over the internet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                connectedDeviceRow
            }
        }
    }

    @ViewBuilder
    private var connectedDeviceRow: some View {
        if let session = environment.connectedSessions.first {
            let diagnostics = diagnosticsViewModel?.snapshot.sessions.first { $0.id == session.id }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.deviceName).bold()
                HStack(spacing: 8) {
                    if let channel = diagnostics?.channel {
                        Text(channel.uppercased())
                    }
                    if let rtt = diagnostics?.rttP50Millis {
                        Text("RTT \(rtt, specifier: "%.0f") ms")
                    } else if let latency = session.latencyMillis {
                        Text("RTT \(latency) ms")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } else {
            Text("No device connected")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Pairing card

    private var pairingCard: some View {
        Card(title: "Pair a device") {
            VStack(alignment: .leading, spacing: 12) {
                if isPairingActive {
                    PairingContentView(onURLChange: { url in lastPairingURLString = url })
                        .frame(maxWidth: .infinity)
                } else {
                    HStack {
                        Button("Pair New Device") {
                            isPairingActive = true
                        }
                        Button(didCopyPairingLink ? "Copied" : "Copy Pairing Link") {
                            copyPairingLink()
                        }
                        .disabled(lastPairingURLString == nil)
                        Spacer()
                    }
                }
            }
        }
    }

    private func copyPairingLink() {
        guard let lastPairingURLString else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lastPairingURLString, forType: .string)
        didCopyPairingLink = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopyPairingLink = false
        }
    }

    // MARK: - Recent activity card

    private var recentActivityCard: some View {
        Card(title: "Recent activity") {
            let events = Array((diagnosticsViewModel?.snapshot.recentEvents ?? []).suffix(10).reversed())
            if events.isEmpty {
                Text("No recent activity.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                        Text(event)
                            .font(.caption.monospaced())
                    }
                }
            }
        }
    }

    // MARK: - Polling

    private func pollServerStatus() async {
        guard statusPollTask == nil else { return }
        statusPollTask = Task {
            while !Task.isCancelled {
                isRunning = await environment.hostService.isRunning
                tcpPort = await environment.hostService.tcpPort
                udpPort = await environment.hostService.udpPort
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func startDiagnosticsPolling() {
        guard diagnosticsViewModel == nil else { return }
        let viewModel = DiagnosticsViewModel(sink: environment.diagnosticsSink)
        diagnosticsViewModel = viewModel
        viewModel.startPolling()
    }
}

/// Small reusable card container so the status/pairing/recent-activity sections read as one system.
private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}
