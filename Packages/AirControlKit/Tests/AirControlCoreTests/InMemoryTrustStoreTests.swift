import Testing
import Foundation
@testable import AirControlCore
import AirControlCrypto

@Suite struct InMemoryTrustStoreTests {
    private func makeRecord(_ byte: UInt8, name: String = "Phone") -> TrustedDeviceRecord {
        TrustedDeviceRecord(
            fingerprint: stubFingerprint(byte),
            name: name,
            model: "iPhone16,1",
            osVersion: "iOS 18.6",
            firstPaired: Date(timeIntervalSince1970: 0),
            lastSeen: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func addThenLookupFindsRecord() async {
        let store = InMemoryTrustStore()
        let record = makeRecord(1)
        #expect(await store.add(record))
        let found = await store.lookup(fingerprint: record.fingerprint)
        #expect(found?.name == "Phone")
    }

    @Test func lookupMissingReturnsNil() async {
        let store = InMemoryTrustStore()
        let found = await store.lookup(fingerprint: stubFingerprint(99))
        #expect(found == nil)
    }

    @Test func listReturnsAllAddedRecords() async {
        let store = InMemoryTrustStore()
        await store.add(makeRecord(1))
        await store.add(makeRecord(2))
        let all = await store.list()
        #expect(all.count == 2)
    }

    @Test func revokeMarksRecordRevokedWithoutDeleting() async {
        let store = InMemoryTrustStore()
        let record = makeRecord(1)
        await store.add(record)
        await store.revoke(fingerprint: record.fingerprint)
        let found = await store.lookup(fingerprint: record.fingerprint)
        #expect(found?.revoked == true)
    }

    @Test func removeDeletesRecord() async {
        let store = InMemoryTrustStore()
        let record = makeRecord(1)
        await store.add(record)
        await store.remove(fingerprint: record.fingerprint)
        let found = await store.lookup(fingerprint: record.fingerprint)
        #expect(found == nil)
    }

    @Test func updateLastSeenChangesTimestamp() async {
        let store = InMemoryTrustStore()
        let record = makeRecord(1)
        await store.add(record)
        let newDate = Date(timeIntervalSince1970: 12345)
        await store.updateLastSeen(fingerprint: record.fingerprint, date: newDate)
        let found = await store.lookup(fingerprint: record.fingerprint)
        #expect(found?.lastSeen == newDate)
    }

    @Test func updateReplacesRecordWholesale() async {
        let store = InMemoryTrustStore()
        var record = makeRecord(1)
        await store.add(record)
        record.allowScripts = true
        record.localAlias = "Devashish's iPhone"
        await store.update(record)
        let found = await store.lookup(fingerprint: record.fingerprint)
        #expect(found?.allowScripts == true)
        #expect(found?.localAlias == "Devashish's iPhone")
    }

    @Test func addFailsWhenAtMaxCapacity() async {
        let store = InMemoryTrustStore(maxRecords: 2)
        #expect(await store.add(makeRecord(1)))
        #expect(await store.add(makeRecord(2)))
        #expect(await store.add(makeRecord(3)) == false)
        #expect(await store.list().count == 2)
    }

    @Test func addExistingFingerprintAtCapacityOverwrites() async {
        let store = InMemoryTrustStore(maxRecords: 1)
        let record = makeRecord(1, name: "Original")
        #expect(await store.add(record))
        var updated = record
        updated.name = "Renamed"
        #expect(await store.add(updated)) // same fingerprint, should not be rejected by the cap
        let found = await store.lookup(fingerprint: record.fingerprint)
        #expect(found?.name == "Renamed")
    }

    @Test func codableRoundTripsThroughHexFingerprint() throws {
        let record = makeRecord(7)
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(TrustedDeviceRecord.self, from: data)
        #expect(decoded == record)
    }
}
