// spec §5.6 — Trusted Devices: table + Revoke (confirmation sheet) + Revoke All. docs/08 §5.2:
// embedded as the main window's "Devices" sidebar section (`Features/MainWindow/DevicesScreen.swift`)
// instead of its own `Window` scene — renamed from `TrustedDevicesWindow` accordingly.
import SwiftUI

struct TrustedDevicesContentView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: TrustedDevicesViewModel?

    var body: some View {
        Group {
            if let viewModel {
                TrustedDevicesList(viewModel: viewModel, allowScriptsGloballyEnabled: environment.settings.allowScriptsGlobal)
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 640, minHeight: 320)
        .onAppear {
            if viewModel == nil {
                viewModel = TrustedDevicesViewModel(store: environment.trustStore)
            }
        }
    }
}

private struct TrustedDevicesList: View {
    @Bindable var viewModel: TrustedDevicesViewModel
    let allowScriptsGloballyEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(viewModel.devices) { device in
                    TrustedDeviceRowView(
                        device: device,
                        allowScriptsGloballyEnabled: allowScriptsGloballyEnabled,
                        onRename: { newName in Task { await viewModel.rename(id: device.id, to: newName) } },
                        onAllowScriptsChanged: { allow in Task { await viewModel.setAllowScripts(allow, forDeviceID: device.id) } },
                        onRevoke: { viewModel.requestRevoke(id: device.id) }
                    )
                }
            }
            if viewModel.devices.isEmpty {
                Text("No trusted devices yet. Pair a phone from the Air Mouse menu.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
            HStack {
                Spacer()
                Button("Revoke All", role: .destructive) {
                    viewModel.requestRevokeAll()
                }
                .disabled(viewModel.devices.isEmpty)
            }
            .padding()
        }
        .task { await viewModel.refresh() }
        .confirmationDialog(
            "Revoke \(viewModel.deviceNamePendingRevoke ?? "this device")?",
            isPresented: Binding(
                get: { viewModel.deviceIDPendingRevoke != nil },
                set: { if !$0 { viewModel.cancelRevoke() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Revoke", role: .destructive) {
                Task { await viewModel.confirmRevoke() }
            }
            Button("Cancel", role: .cancel) { viewModel.cancelRevoke() }
        } message: {
            Text("It will disconnect now and must scan a new QR to reconnect.")
        }
        .confirmationDialog(
            "Revoke all trusted devices?",
            isPresented: $viewModel.isPendingRevokeAll,
            titleVisibility: .visible
        ) {
            Button("Revoke All", role: .destructive) {
                Task { await viewModel.confirmRevokeAll() }
            }
            Button("Cancel", role: .cancel) { viewModel.cancelRevokeAll() }
        } message: {
            Text("Every device will disconnect and must scan a new QR to reconnect.")
        }
        .alert("Couldn't update trusted devices", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
