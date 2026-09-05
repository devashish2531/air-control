// Tests/KnownHostsStoreTests.swift
// `KnownHostsStore` — the `TrustStoreProtocol` conformer over `DocumentStore` (spec §3.2.4's
// client-side trusted-host persistence) plus the connection-info sibling document and the
// last-used-host `UserDefaults` key (spec §4.5.5 auto-connect). All against a temp-directory
// `DocumentStore` — no network, no real Keychain.

import Foundation
import Testing
import AirMouseCore
import AirMouseCrypto
import AirMouseProtocol
@testable import Air_Mouse

private func makeStore() -> KnownHostsStore {
    KnownHostsStore(documentStore: DocumentStore(rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("KnownHostsStoreTests-\(UUID().uuidString)")))
}

private func makeFingerprint(_ byte: UInt8) -> Fingerprint {
    Fingerprint(bytes: [UInt8](repeating: byte, count: 32))!
}

private func makeRecord(fingerprint: Fingerprint, name: String = "Devashish's Mac mini") -> TrustedDeviceRecord {
    TrustedDeviceRecord(fingerprint: fingerprint, name: name, model: "Mac15,6", osVersion: "macOS 15.0", firstPaired: Date(), lastSeen: Date())
}

@Suite struct KnownHostsStoreTests {
    // MARK: - TrustStoreProtocol CRUD

    @Test func addThenListReturnsTheRecord() async {
        let store = makeStore()
        let fingerprint = makeFingerprint(1)
        await store.add(makeRecord(fingerprint: fingerprint))

        let all = await store.list()
        #expect(all.map(\.fingerprint) == [fingerprint])
    }

    @Test func lookupFindsByExactFingerprint() async {
        let store = makeStore()
        let fingerprint = makeFingerprint(2)
        await store.add(makeRecord(fingerprint: fingerprint, name: "Office Mac"))

        let found = await store.lookup(fingerprint: fingerprint)
        #expect(found?.name == "Office Mac")
        #expect(await store.lookup(fingerprint: makeFingerprint(99)) == nil)
    }

    @Test func addTwiceWithSameFingerprintUpdatesInPlaceRatherThanDuplicating() async {
        let store = makeStore()
        let fingerprint = makeFingerprint(3)
        await store.add(makeRecord(fingerprint: fingerprint, name: "Old Name"))
        await store.add(makeRecord(fingerprint: fingerprint, name: "New Name"))

        let all = await store.list()
        #expect(all.count == 1)
        #expect(all.first?.name == "New Name")
    }

    @Test func revokeMarksRevokedWithoutDeletingTheRecord() async {
        let store = makeStore()
        let fingerprint = makeFingerprint(4)
        await store.add(makeRecord(fingerprint: fingerprint))

        await store.revoke(fingerprint: fingerprint)

        let record = await store.lookup(fingerprint: fingerprint)
        #expect(record?.revoked == true)
    }

    @Test func updateLastSeenChangesOnlyThatField() async {
        let store = makeStore()
        let fingerprint = makeFingerprint(5)
        await store.add(makeRecord(fingerprint: fingerprint))
        let newDate = Date(timeIntervalSince1970: 1_700_000_000)

        await store.updateLastSeen(fingerprint: fingerprint, date: newDate)

        let record = await store.lookup(fingerprint: fingerprint)
        #expect(record?.lastSeen == newDate)
    }

    @Test func updateReplacesTheWholeRecord() async {
        let store = makeStore()
        let fingerprint = makeFingerprint(6)
        var record = makeRecord(fingerprint: fingerprint)
        await store.add(record)

        record.localAlias = "Basement Mac"
        record.allowScripts = true
        await store.update(record)

        let reloaded = await store.lookup(fingerprint: fingerprint)
        #expect(reloaded?.localAlias == "Basement Mac")
        #expect(reloaded?.allowScripts == true)
    }

    @Test func removeDeletesTheRecordAndItsConnectionInfo() async {
        let store = makeStore()
        let fingerprint = makeFingerprint(7)
        await store.add(makeRecord(fingerprint: fingerprint))
        await store.setConnectionInfo(KnownHostConnectionInfo(tcpPort: 47800, udpPort: 47800), fingerprint: fingerprint)

        await store.remove(fingerprint: fingerprint)

        #expect(await store.lookup(fingerprint: fingerprint) == nil)
        #expect(await store.connectionInfo(fingerprint: fingerprint) == nil)
    }

    @Test func addRespectsMaxTrustedHostsPerClient() async {
        let store = makeStore()
        for index in 0..<ProtocolConstants.maxTrustedHostsPerClient {
            let accepted = await store.add(makeRecord(fingerprint: makeFingerprint(UInt8(index))))
            #expect(accepted, "expected slot \(index) to be accepted")
        }
        let overflowAccepted = await store.add(makeRecord(fingerprint: makeFingerprint(255)))
        #expect(overflowAccepted == false)
        #expect(await store.list().count == ProtocolConstants.maxTrustedHostsPerClient)
    }

    // MARK: - Connection info (spec §3.2.4's client-only fields)

    @Test func connectionInfoRoundTrips() async {
        let store = makeStore()
        let fingerprint = makeFingerprint(8)
        let info = KnownHostConnectionInfo(tcpPort: 47800, udpPort: 47801, qrAddresses: ["10.0.1.5"], hostID: Data([0x01, 0x02]))

        await store.setConnectionInfo(info, fingerprint: fingerprint)

        let reloaded = await store.connectionInfo(fingerprint: fingerprint)
        #expect(reloaded == info)
    }

    @Test func recordSuccessfulConnectionIsMostRecentFirstAndCapsAtSix() async {
        let store = makeStore()
        let fingerprint = makeFingerprint(9)
        await store.setConnectionInfo(KnownHostConnectionInfo(tcpPort: 47800, udpPort: 47800), fingerprint: fingerprint)

        for index in 0..<8 {
            await store.recordSuccessfulConnection(fingerprint: fingerprint, address: "10.0.0.\(index)", at: Date(timeIntervalSince1970: Double(index)))
        }

        let info = await store.connectionInfo(fingerprint: fingerprint)
        #expect(info?.lastKnownAddresses.count == KnownHostConnectionInfo.maxLastKnownAddresses)
        // Newest (index 7, latest timestamp) first.
        #expect(info?.lastKnownAddresses.first?.address == "10.0.0.7")
        // The oldest two (index 0, 1) were evicted.
        #expect(info?.lastKnownAddresses.map(\.address).contains("10.0.0.0") == false)
    }

    @Test func recordSuccessfulConnectionMovesARepeatedAddressToTheFront() async {
        let store = makeStore()
        let fingerprint = makeFingerprint(10)
        await store.setConnectionInfo(KnownHostConnectionInfo(tcpPort: 47800, udpPort: 47800), fingerprint: fingerprint)

        await store.recordSuccessfulConnection(fingerprint: fingerprint, address: "10.0.0.1", at: Date(timeIntervalSince1970: 0))
        await store.recordSuccessfulConnection(fingerprint: fingerprint, address: "10.0.0.2", at: Date(timeIntervalSince1970: 1))
        await store.recordSuccessfulConnection(fingerprint: fingerprint, address: "10.0.0.1", at: Date(timeIntervalSince1970: 2))

        let info = await store.connectionInfo(fingerprint: fingerprint)
        #expect(info?.lastKnownAddresses.map(\.address) == ["10.0.0.1", "10.0.0.2"])
    }

    // MARK: - Last-used host (spec §4.5.5 auto-connect)

    @Test func lastUsedHostRoundTripsThroughUserDefaults() {
        let store = makeStore()
        let fingerprint = makeFingerprint(11)
        defer { store.setLastUsedHost(fingerprint: nil) }

        store.setLastUsedHost(fingerprint: fingerprint)
        #expect(store.lastUsedHostFingerprintHex == fingerprint.hexString)

        store.setLastUsedHost(fingerprint: nil)
        #expect(store.lastUsedHostFingerprintHex == nil)
    }
}
