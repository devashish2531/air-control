// Tests/DevicesTests.swift
// `DevicesScreen.unpaired(discovered:knownHostRows:)` — the pure filter behind "Other Macs on
// this network" (spec §4.1.3: browse results without a trusted record) — plus `KnownHostRow`
// construction sanity. UI chrome itself (List/swipe actions/sheets) isn't unit-tested here; this
// covers the one piece of real logic `DevicesScreen` owns.

import Foundation
import Testing
import AirControlCore
import AirControlCrypto
import Network
@testable import Air_Control

private func makeHost(id: Data, name: String = "Some Mac") -> DiscoveredHost {
    DiscoveredHost(
        id: id,
        name: name,
        machineModel: "Mac15,6",
        fingerprintPrefix: Data([UInt8](repeating: 0, count: 16)),
        tcpPort: 47800,
        udpPort: 47800,
        supportedVersions: [1],
        endpoint: .hostPort(host: "10.0.0.1", port: 47800)
    )
}

private func makeRow(hostID: Data?, fingerprintByte: UInt8) -> KnownHostRow {
    let fingerprint = Fingerprint(bytes: [UInt8](repeating: fingerprintByte, count: 32))!
    let record = TrustedDeviceRecord(fingerprint: fingerprint, name: "Trusted Mac", model: "Mac15,6", osVersion: "macOS 15.0", firstPaired: Date(), lastSeen: Date())
    return KnownHostRow(record: record, status: .notFound, hostID: hostID)
}

@Suite struct DevicesTests {
    @Test func hostsWithNoTrustedRecordAreConsideredUnpaired() {
        let discovered = [makeHost(id: Data([0x01])), makeHost(id: Data([0x02]))]
        let unpaired = DevicesScreen.unpaired(discovered: discovered, knownHostRows: [])
        #expect(Set(unpaired.map(\.id)) == Set(discovered.map(\.id)))
    }

    @Test func aHostMatchingATrustedRecordsHostIDIsExcluded() {
        let pairedID = Data([0x01])
        let discovered = [makeHost(id: pairedID), makeHost(id: Data([0x02]))]
        let rows = [makeRow(hostID: pairedID, fingerprintByte: 1)]

        let unpaired = DevicesScreen.unpaired(discovered: discovered, knownHostRows: rows)

        #expect(unpaired.map(\.id) == [Data([0x02])])
    }

    @Test func aTrustedRecordWithNoKnownHostIDExcludesNothing() {
        // spec deviation noted in the final report: not every `TrustedDeviceRecord` has a
        // recorded host ID (only ones paired through this build's `KnownHostsStore` do) — such a
        // record simply can't be matched against a live browse result, so nothing is hidden for it.
        let discovered = [makeHost(id: Data([0x01]))]
        let rows = [makeRow(hostID: nil, fingerprintByte: 1)]

        let unpaired = DevicesScreen.unpaired(discovered: discovered, knownHostRows: rows)

        #expect(unpaired.map(\.id) == [Data([0x01])])
    }

    @Test func emptyDiscoveredListProducesNoUnpairedRows() {
        let rows = [makeRow(hostID: Data([0x01]), fingerprintByte: 1)]
        #expect(DevicesScreen.unpaired(discovered: [], knownHostRows: rows).isEmpty)
    }

    @Test func knownHostRowIdentityIsTheTrustedRecordsFingerprintHex() {
        let row = makeRow(hostID: Data([0x01]), fingerprintByte: 42)
        #expect(row.id == row.record.fingerprint.hexString)
    }

    @Test func forgettingAKnownHostMakesItReappearAsUnpaired() {
        // spec item 3: "After Forget, a discovered unpaired Mac shows a 'Pair' affordance" — driven
        // entirely by `unpaired`'s own filter once the record is gone from `knownHostRows`.
        let hostID = Data([0x01])
        let discovered = [makeHost(id: hostID, name: "Devashish's Mac mini")]
        let rowsBeforeForget = [makeRow(hostID: hostID, fingerprintByte: 9)]
        #expect(DevicesScreen.unpaired(discovered: discovered, knownHostRows: rowsBeforeForget).isEmpty)

        let rowsAfterForget: [KnownHostRow] = [] // `ConnectionManager.forget` removes the row and calls `refreshKnownHostRows()`.
        #expect(DevicesScreen.unpaired(discovered: discovered, knownHostRows: rowsAfterForget).map(\.id) == [hostID])
    }
}

// MARK: - Failure-title copy (spec item 3: "for `hostIdentityChanged` the destructive action
// reads 'Forget and pair again'") — pure, no manager needed.

@Suite struct DevicesForgetActionTitleTests {
    @Test func hostIdentityChangedUsesForgetAndPairAgain() {
        #expect(DevicesScreen.forgetActionTitle(for: .hostIdentityChanged) == "Forget and pair again")
    }

    @Test func everyOtherFailureUsesTheUsualForgetMacWording() {
        #expect(DevicesScreen.forgetActionTitle(for: .hostUnreachable(hostName: "Marcus's Mac")) == "Forget Mac")
        #expect(DevicesScreen.forgetActionTitle(for: .hostRefusedUntrusted) == "Forget Mac")
        #expect(DevicesScreen.forgetActionTitle(for: .tlsHandshakeFailed(detail: "timed out")) == "Forget Mac")
    }
}

// MARK: - Connect-failure alert flow with a mock manager (spec item 3: "on failure an alert with
// the real reason") — `@MainActor` because `DeviceConnectAttemptObserving` (and the real
// `ConnectionManager` it mirrors) are MainActor-isolated.

@MainActor
private final class MockDeviceConnectManager: DeviceConnectAttemptObserving {
    // Fully qualified: `AirControlCore` (imported above for `TrustedDeviceRecord`/`Fingerprint`)
    // also exports a `ConnectionState`, ambiguous with this app's own shell-facing one otherwise.
    var connectionState: Air_Control.ConnectionState
    var lastError: AppError?

    init(connectionState: Air_Control.ConnectionState, lastError: AppError?) {
        self.connectionState = connectionState
        self.lastError = lastError
    }
}

@MainActor
@Suite struct DevicesConnectFailureAlertTests {
    private func makeRecord(fingerprintByte: UInt8 = 1) -> TrustedDeviceRecord {
        let fingerprint = Fingerprint(bytes: [UInt8](repeating: fingerprintByte, count: 32))!
        return TrustedDeviceRecord(fingerprint: fingerprint, name: "Marcus's Mac", model: "Mac15,6", osVersion: "macOS 15.0", firstPaired: Date(), lastSeen: Date())
    }

    @Test func noManagerMeansNoAlert() {
        #expect(DevicesScreen.failureAlert(afterConnectingTo: makeRecord(), manager: nil) == nil)
    }

    @Test func successfulConnectionShowsNoAlert() {
        let mock = MockDeviceConnectManager(connectionState: .connected(hostName: "Marcus's Mac"), lastError: nil)
        #expect(DevicesScreen.failureAlert(afterConnectingTo: makeRecord(), manager: mock) == nil)
    }

    @Test func stillConnectingShowsNoAlertYet() {
        let mock = MockDeviceConnectManager(connectionState: .connecting, lastError: nil)
        #expect(DevicesScreen.failureAlert(afterConnectingTo: makeRecord(), manager: mock) == nil)
    }

    @Test func failedConnectionSurfacesTheRealErrorForTheSameRecord() {
        let record = makeRecord()
        let mock = MockDeviceConnectManager(connectionState: .failed(reason: "Couldn't reach"), lastError: .hostRefusedUntrusted)
        let alert = DevicesScreen.failureAlert(afterConnectingTo: record, manager: mock)
        #expect(alert?.error == .hostRefusedUntrusted)
        #expect(alert?.record == record)
    }

    @Test func hostIdentityChangedIsSurfacedVerbatim() {
        let mock = MockDeviceConnectManager(connectionState: .failed(reason: "identity changed"), lastError: .hostIdentityChanged)
        let alert = DevicesScreen.failureAlert(afterConnectingTo: makeRecord(), manager: mock)
        #expect(alert?.error == .hostIdentityChanged)
    }

    @Test func failedStateWithNoLastErrorShowsNoAlert() {
        // Defensive: `lastError` and `connectionState` are two separate published properties: if
        // they're ever momentarily out of sync, don't show a blank/stale alert.
        let mock = MockDeviceConnectManager(connectionState: .failed(reason: "x"), lastError: nil)
        #expect(DevicesScreen.failureAlert(afterConnectingTo: makeRecord(), manager: mock) == nil)
    }
}
