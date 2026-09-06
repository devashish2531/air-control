import Foundation
import AirControlCrypto
import AirControlProtocol

/// An in-memory `TrustStoreProtocol` — no Keychain, no disk — for tests and `aircontrol-cli`
/// (arch §3.1's public API table lists this alongside `TrustedDeviceRecord`).
public actor InMemoryTrustStore: TrustStoreProtocol {
    private var records: [String: TrustedDeviceRecord] = [:] // keyed by fingerprint.hexString
    private let maxRecords: Int

    public init(maxRecords: Int = ProtocolConstants.maxTrustedDevicesPerHost) {
        self.maxRecords = maxRecords
    }

    public func list() -> [TrustedDeviceRecord] {
        Array(records.values)
    }

    public func lookup(fingerprint: Fingerprint) -> TrustedDeviceRecord? {
        records[fingerprint.hexString]
    }

    @discardableResult
    public func add(_ record: TrustedDeviceRecord) -> Bool {
        if records[record.id] == nil && records.count >= maxRecords {
            return false
        }
        records[record.id] = record
        return true
    }

    public func revoke(fingerprint: Fingerprint) {
        records[fingerprint.hexString]?.revoked = true
    }

    public func updateLastSeen(fingerprint: Fingerprint, date: Date) {
        records[fingerprint.hexString]?.lastSeen = date
    }

    public func update(_ record: TrustedDeviceRecord) {
        records[record.id] = record
    }

    public func remove(fingerprint: Fingerprint) {
        records.removeValue(forKey: fingerprint.hexString)
    }
}
