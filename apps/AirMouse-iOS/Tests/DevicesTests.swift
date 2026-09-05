// Tests/DevicesTests.swift
// `DevicesScreen.unpaired(discovered:knownHostRows:)` — the pure filter behind "Other Macs on
// this network" (spec §4.1.3: browse results without a trusted record) — plus `KnownHostRow`
// construction sanity. UI chrome itself (List/swipe actions/sheets) isn't unit-tested here; this
// covers the one piece of real logic `DevicesScreen` owns.

import Foundation
import Testing
import AirMouseCore
import AirMouseCrypto
import Network
@testable import Air_Mouse

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
}
