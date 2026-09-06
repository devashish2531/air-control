// TrustStoreTests — spec §3.2.4 persistence, §5.6 revoke/rename/allowScripts, §7.6 20-device cap.
@testable import Air_Control
import AirControlCrypto
import Foundation
import Testing

@Suite("TrustStore")
struct TrustStoreTests {
    private func makeStore() -> (TrustStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TrustStoreTests-\(UUID().uuidString)")
        let documentStore = DocumentStore(baseDirectory: dir)
        return (TrustStore(documentStore: documentStore), dir)
    }

    private func fingerprint(_ seed: UInt8) -> Fingerprint {
        Fingerprint(bytes: [UInt8](repeating: seed, count: 32))!
    }

    @Test("add + list round trip")
    func addAndList() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fp = fingerprint(1)
        let record = CoreTrustedDeviceRecord(
            fingerprint: fp, name: "iPhone", model: "iPhone16,1", osVersion: "iOS 18.6",
            firstPaired: Date(), lastSeen: Date(), allowScripts: false, revoked: false
        )
        let added = await store.add(record)
        #expect(added)

        let list = await store.list()
        #expect(list.count == 1)
        #expect(list.first?.fingerprint == fp)

        let looked = await store.lookup(fingerprint: fp)
        #expect(looked?.name == "iPhone")
    }

    @Test("persists across a fresh instance over the same DocumentStore")
    func persistsAcrossInstances() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TrustStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let documentStore = DocumentStore(baseDirectory: dir)

        let fp = fingerprint(2)
        let store1 = TrustStore(documentStore: documentStore)
        await store1.add(CoreTrustedDeviceRecord(
            fingerprint: fp, name: "iPad", model: "iPad14,1", osVersion: "iPadOS 18",
            firstPaired: Date(), lastSeen: Date(), allowScripts: false, revoked: false
        ))

        let store2 = TrustStore(documentStore: documentStore)
        let list = await store2.list()
        #expect(list.count == 1)
        #expect(list.first?.name == "iPad")
    }

    @Test("revoke marks revoked, excludes from trustedFingerprints, notifies onRevoked")
    func revoke() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fp = fingerprint(3)
        await store.add(CoreTrustedDeviceRecord(
            fingerprint: fp, name: "Phone", model: "m", osVersion: "os",
            firstPaired: Date(), lastSeen: Date(), allowScripts: false, revoked: false
        ))
        #expect(await store.trustedFingerprints().contains(fp))

        actor Flag { var revokedFP: Fingerprint?; func set(_ fp: Fingerprint) { revokedFP = fp } }
        let flag = Flag()
        await store.setOnRevoked { fp in await flag.set(fp) }

        await store.revoke(fingerprint: fp)
        #expect(!(await store.trustedFingerprints().contains(fp)))
        let record = await store.lookup(fingerprint: fp)
        #expect(record?.revoked == true)

        // onRevoked is invoked synchronously inside `revoke`, so it has already run by the time we get here.
        #expect(await flag.revokedFP == fp)
    }

    @Test("shell TrustStoring surface: rename, setAllowScripts, revoke by id, revokeAll")
    func shellSurface() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fp = fingerprint(4)
        await store.add(CoreTrustedDeviceRecord(
            fingerprint: fp, name: "Original", model: "m", osVersion: "os",
            firstPaired: Date(), lastSeen: Date(), allowScripts: false, revoked: false
        ))
        let id = fp.hexString

        try await store.rename(id: id, to: "Renamed")
        var devices = await store.listDevices()
        #expect(devices.first?.name == "Renamed")

        try await store.setAllowScripts(true, forDeviceID: id)
        devices = await store.listDevices()
        #expect(devices.first?.allowScripts == true)

        try await store.revoke(id: id)
        devices = await store.listDevices()
        #expect(devices.first?.revoked == true)

        try await store.revokeAll()
        // revokeAll marks every record revoked (spec keeps the record, does not delete it).
        devices = await store.listDevices()
        #expect(devices.allSatisfy { $0.revoked })
    }

    @Test("20-device cap rejects a 21st new device")
    func deviceCap() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        for i in 0..<20 {
            let added = await store.add(CoreTrustedDeviceRecord(
                fingerprint: fingerprint(UInt8(i + 10)), name: "d\(i)", model: "m", osVersion: "os",
                firstPaired: Date(), lastSeen: Date(), allowScripts: false, revoked: false
            ))
            #expect(added)
        }
        let overflowAdded = await store.add(CoreTrustedDeviceRecord(
            fingerprint: fingerprint(200), name: "overflow", model: "m", osVersion: "os",
            firstPaired: Date(), lastSeen: Date(), allowScripts: false, revoked: false
        ))
        #expect(!overflowAdded)
        #expect(await store.list().count == 20)
    }

    @Test("revoke deletes any matching Keychain certificate item best-effort (no crash if absent)")
    func revokeDeletesKeychainItemBestEffort() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fp = fingerprint(5)
        await store.add(CoreTrustedDeviceRecord(
            fingerprint: fp, name: "n", model: "m", osVersion: "os",
            firstPaired: Date(), lastSeen: Date(), allowScripts: false, revoked: false
        ))
        // No corresponding Keychain item was ever created in this test; revoke must still succeed.
        await store.revoke(fingerprint: fp)
        #expect(await store.lookup(fingerprint: fp)?.revoked == true)
    }
}
