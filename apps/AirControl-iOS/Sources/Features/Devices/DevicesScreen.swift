// Features/Devices/DevicesScreen.swift
// spec §4.1.3: trusted hosts list (name, model glyph, status, last-connected relative time),
// "Other Macs on this network" (unpaired browse results → explains pairing needs the QR),
// toolbar Scan QR, swipe actions Connect/Forget (confirmation), empty state after 5 s of browsing
// (guidance + Scan QR + Check permission), local-network-denied banner (spec §4.5.5 / §9).
//
// Drives `ConnectionManager` by downcasting `environment.connection as? ConnectionManager` — see
// `ConnectionManager+Environment.swift`'s header comment for why.

import SwiftUI
import UIKit
import AirControlCore

public struct DevicesScreen: View {
    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var showScanQR = false
    @State private var recordPendingForget: TrustedDeviceRecord?
    @State private var browsingStartedAt: Date?
    @State private var showEmptyStateGuidance = false
    @State private var selectedUnpairedHost: DiscoveredHost?
    /// Set for the duration of one `connectToKnownHost` attempt started from this screen (spec
    /// item 3: "tapping a known Mac shows progress").
    @State private var connectingRecordID: String?
    /// Non-`nil` only when the attempt above actually failed — drives the real-reason alert (spec
    /// item 3: "on failure an alert with the real reason").
    @State private var connectFailure: ConnectFailurePresentation?

    public init() {}

    private var manager: ConnectionManager? { environment.connection as? ConnectionManager }

    public var body: some View {
        List {
            if manager?.browseState == .localNetworkDenied {
                localNetworkDeniedBanner
            }

            if let rows = manager?.knownHostRows, !rows.isEmpty {
                Section {
                    ForEach(rows) { row in
                        knownHostRow(row)
                    }
                } header: {
                    Text("Your Macs", comment: "Devices screen: trusted hosts section header")
                }
            }

            if let unpaired = unpairedDiscoveredHosts, !unpaired.isEmpty {
                Section {
                    ForEach(unpaired, id: \.id) { host in
                        Button {
                            selectedUnpairedHost = host
                        } label: {
                            unpairedHostRow(host)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Other Macs on this network", comment: "Devices screen: unpaired hosts section header")
                }
            }

            if (manager?.knownHostRows.isEmpty ?? true) && (unpairedDiscoveredHosts?.isEmpty ?? true) && showEmptyStateGuidance {
                emptyStateSection
            }
        }
        .navigationTitle(Text("Devices", comment: "Devices screen navigation title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showScanQR = true
                } label: {
                    Label(String(localized: "Scan QR", comment: "Devices screen: scan QR toolbar button"), systemImage: "qrcode.viewfinder")
                }
            }
        }
        .onAppear {
            manager?.startBrowsing()
            browsingStartedAt = Date()
            Task { await manager?.refreshKnownHostRows() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { showEmptyStateGuidance = true }
        }
        .onDisappear {
            manager?.stopBrowsing()
        }
        .fullScreenCover(isPresented: $showScanQR) {
            NavigationStack { PairingScreen() }
        }
        .sheet(item: $selectedUnpairedHost) { host in
            unpairedHostExplanationSheet(host)
        }
        .confirmationDialog(
            Text("Forget this Mac?", comment: "Devices screen: forget confirmation title"),
            isPresented: Binding(
                get: { recordPendingForget != nil },
                set: { if !$0 { recordPendingForget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Forget Mac", comment: "Error recovery action: forgets the trusted host"), role: .destructive) {
                if let record = recordPendingForget {
                    Task { await manager?.forget(record) }
                }
                recordPendingForget = nil
            }
            Button(String(localized: "Cancel", comment: "Error recovery action: cancels reconnect and returns to Devices"), role: .cancel) {
                recordPendingForget = nil
            }
        } message: {
            Text("This removes the pairing and its saved credentials. You'll need to scan the QR code again to reconnect.", comment: "Devices screen: forget confirmation message")
        }
        .alert(
            connectFailure?.error.presentation.title ?? "",
            isPresented: Binding(
                get: { connectFailure != nil },
                set: { if !$0 { connectFailure = nil } }
            ),
            presenting: connectFailure
        ) { failure in
            Button(String(localized: "Try Again", comment: "Devices screen: retries a failed connect-to-known-host attempt")) {
                attemptConnect(failure.record)
            }
            Button(Self.forgetActionTitle(for: failure.error), role: .destructive) {
                Task { await manager?.forget(failure.record) }
            }
            Button(String(localized: "Cancel", comment: "Error recovery action: cancels reconnect and returns to Devices"), role: .cancel) {}
        } message: { failure in
            Text(failure.error.presentation.message)
        }
    }

    // MARK: - Rows

    private func knownHostRow(_ row: KnownHostRow) -> some View {
        let isLive = manager?.discoveredHosts.contains { discovered in
            row.hostID.map { discovered.id == $0 } ?? false
        } ?? false
        let status: KnownHostRow.Status = row.status == .connected ? .connected : (isLive ? .available : .notFound)

        return HStack(spacing: 12) {
            Image(systemName: "laptopcomputer")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.record.localAlias ?? row.record.name)
                    .font(.body.weight(.medium))
                Text(statusLabel(status, lastSeen: row.record.lastSeen))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if connectingRecordID == row.record.id {
                ProgressView()
            } else if status == .connected {
                Circle().fill(.green).frame(width: 8, height: 8)
            } else if status == .available {
                Circle().fill(.yellow).frame(width: 8, height: 8)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(String(localized: "Forget Mac", comment: "Error recovery action: forgets the trusted host"), role: .destructive) {
                recordPendingForget = row.record
            }
            if status != .connected {
                Button(String(localized: "Retry", comment: "Error recovery action: retries the failed connection attempt")) {
                    attemptConnect(row.record)
                }
                .tint(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard status != .connected else { return }
            attemptConnect(row.record)
        }
    }

    /// spec item 3: drives `connectingRecordID` for the row's progress indicator, then — once the
    /// attempt settles — surfaces `connectFailure` if (and only if) it actually failed.
    private func attemptConnect(_ record: TrustedDeviceRecord) {
        guard connectingRecordID == nil else { return }
        connectingRecordID = record.id
        Task {
            await manager?.connectToKnownHost(record)
            connectingRecordID = nil
            connectFailure = Self.failureAlert(afterConnectingTo: record, manager: manager)
        }
    }

    private func unpairedHostRow(_ host: DiscoveredHost) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "laptopcomputer")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text("Not paired", comment: "Devices screen: unpaired host badge")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func unpairedHostExplanationSheet(_ host: DiscoveredHost) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "qrcode")
                .font(.system(size: 40))
            Text(host.name)
                .font(.headline)
            Text("To connect to this Mac, scan the pairing QR code shown in the Air Control menu on your Mac.", comment: "Devices screen: unpaired host explanation")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                selectedUnpairedHost = nil
                showScanQR = true
            } label: {
                Text("Scan QR", comment: "Error recovery action: navigates to the QR scanner")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 32)
        .presentationDetents([.medium])
    }

    // MARK: - Empty state (AM-DP-01)

    private var emptyStateSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("No Macs found yet", comment: "Devices screen empty state title")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    Label("Is the Air Control helper running on your Mac?", systemImage: "questionmark.circle")
                    Label("Are both devices on the same Wi-Fi?", systemImage: "wifi")
                    Label("Is Local Network access allowed?", systemImage: "network")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                HStack {
                    Button(String(localized: "Scan QR", comment: "Error recovery action: navigates to the QR scanner")) {
                        showScanQR = true
                    }
                    .buttonStyle(.bordered)
                    Button(String(localized: "Check permission", comment: "Error recovery action: re-checks Local Network permission")) {
                        manager?.stopBrowsing()
                        manager?.startBrowsing()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var localNetworkDeniedBanner: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Local network access is off", systemImage: "wifi.exclamationmark")
                    .font(.headline)
                Text("Air Control can't see your Mac until you allow Local Network access in Settings.", comment: "Devices screen: local network denied banner")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(String(localized: "Open Settings", comment: "Error recovery action: deep-links to iOS Settings for this app")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Connect-failure alert (spec item 3)

    /// `nil` unless the just-finished `connectToKnownHost` attempt actually failed.
    static func failureAlert(afterConnectingTo record: TrustedDeviceRecord, manager: (any DeviceConnectAttemptObserving)?) -> ConnectFailurePresentation? {
        guard let manager, case .failed = manager.connectionState, let error = manager.lastError else { return nil }
        return ConnectFailurePresentation(record: record, error: error)
    }

    /// spec item 3: "for `hostIdentityChanged` the destructive action reads 'Forget and pair
    /// again'" — every other failure keeps the usual "Forget Mac" wording.
    nonisolated static func forgetActionTitle(for error: AppError) -> String {
        if case .hostIdentityChanged = error {
            return String(localized: "Forget and pair again", comment: "Devices screen: destructive action when the Mac's identity changed")
        }
        return String(localized: "Forget Mac", comment: "Error recovery action: forgets the trusted host")
    }

    // MARK: - Helpers

    private var unpairedDiscoveredHosts: [DiscoveredHost]? {
        guard let manager else { return nil }
        return Self.unpaired(discovered: manager.discoveredHosts, knownHostRows: manager.knownHostRows)
    }

    /// Pure filter, split out for unit testing (spec §4.1.3: "Other Macs on this network" excludes
    /// anything already trusted, matched by TXT/QR host ID).
    // `nonisolated`: pure data, no `View`/`@State` touched — `DevicesScreen` being a `View`
    // (implicitly `@MainActor`) would otherwise force this test-friendly helper onto the main
    // actor too, which crashed `DevicesTests`' plain (non-`@MainActor`) test functions at runtime
    // when Swift Testing ran them off the main thread.
    nonisolated static func unpaired(discovered: [DiscoveredHost], knownHostRows: [KnownHostRow]) -> [DiscoveredHost] {
        let pairedHostIDs = Set(knownHostRows.compactMap(\.hostID))
        return discovered.filter { !pairedHostIDs.contains($0.id) }
    }

    private func statusLabel(_ status: KnownHostRow.Status, lastSeen: Date) -> String {
        switch status {
        case .connected:
            return String(localized: "Connected", comment: "Devices screen: host status")
        case .available:
            return String(localized: "Available", comment: "Devices screen: host status")
        case .notFound:
            let formatter = RelativeDateTimeFormatter()
            return String(localized: "Not found · Last seen \(formatter.localizedString(for: lastSeen, relativeTo: Date()))", comment: "Devices screen: host status with relative last-seen time")
        }
    }
}

// MARK: - Connect-failure alert test seam (spec item 3)

/// One failed `connectToKnownHost` attempt, ready to present — the record it was for (so
/// "Try Again"/"Forget Mac" know what to act on) and the real `AppError` (spec item 3: "an alert
/// with the real reason").
struct ConnectFailurePresentation: Identifiable, Equatable {
    let record: TrustedDeviceRecord
    let error: AppError
    var id: String { record.id }
}

/// What `DevicesScreen.attemptConnect`'s failure decision needs from a connection manager —
/// narrow enough that a test can supply a fake without a real `NWConnection`/Keychain (mirrors
/// `DevicesScreen.unpaired`'s own "extract the pure decision, mock the seam" pattern).
/// `ConnectionManager`'s `connectionState`/`lastError` are `private(set)`, so a real instance
/// can't have its state puppeted from a test either — a fake conforming to this protocol is the
/// only way to drive `DevicesScreen.failureAlert` deterministically without a live network attempt.
@MainActor
protocol DeviceConnectAttemptObserving: AnyObject {
    var connectionState: ConnectionState { get }
    var lastError: AppError? { get }
}

extension ConnectionManager: DeviceConnectAttemptObserving {}

#Preview {
    NavigationStack {
        DevicesScreen()
            .environment(\.appEnvironment, .preview())
    }
}
