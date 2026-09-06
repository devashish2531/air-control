@testable import Air_Control
import Foundation

/// Test double for `TrustStoring` that records calls so tests can assert on view-model → store wiring
/// without touching the Keychain or a real `TrustStore` actor.
actor MockTrustStore: TrustStoring {
    private(set) var devices: [TrustedDeviceRecord]
    private(set) var revokedIDs: [String] = []
    private(set) var revokeAllCallCount = 0
    var shouldFailRevoke = false

    init(devices: [TrustedDeviceRecord] = []) {
        self.devices = devices
    }

    func listDevices() async -> [TrustedDeviceRecord] { devices }

    func revoke(id: String) async throws {
        if shouldFailRevoke {
            throw TrustStoreError.notFound(id: id)
        }
        guard devices.contains(where: { $0.id == id }) else { throw TrustStoreError.notFound(id: id) }
        devices.removeAll { $0.id == id }
        revokedIDs.append(id)
    }

    func revokeAll() async throws {
        revokeAllCallCount += 1
        devices.removeAll()
    }

    func setAllowScripts(_ allow: Bool, forDeviceID id: String) async throws {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { throw TrustStoreError.notFound(id: id) }
        devices[index].allowScripts = allow
    }

    func rename(id: String, to newName: String) async throws {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { throw TrustStoreError.notFound(id: id) }
        devices[index].name = newName
    }
}

extension TrustedDeviceRecord {
    static func fixture(
        id: String = "device-1",
        name: String = "Dev's iPhone",
        model: String = "iPhone16,2",
        osVersion: String = "18.0",
        fingerprintShort: String = "deadbeef",
        allowScripts: Bool = false,
        revoked: Bool = false
    ) -> TrustedDeviceRecord {
        TrustedDeviceRecord(
            id: id,
            name: name,
            model: model,
            osVersion: osVersion,
            fingerprintShort: fingerprintShort,
            firstPaired: Date(timeIntervalSince1970: 0),
            lastSeen: Date(timeIntervalSince1970: 0),
            allowScripts: allowScripts,
            revoked: revoked
        )
    }
}
