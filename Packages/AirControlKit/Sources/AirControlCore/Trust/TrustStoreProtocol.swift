import Foundation
import AirControlCrypto

/// Storage for trusted-device records (spec §3.2.4). Keychain-backed implementations live in the
/// apps (arch §3.1: "Keychain-backed implementations live in the apps"); `AirControlCore` only
/// defines the shape and ships `InMemoryTrustStore` for tests and `aircontrol-cli`.
public protocol TrustStoreProtocol: Sendable {
    /// All records, revoked or not, in no particular order.
    func list() async -> [TrustedDeviceRecord]
    /// Looks up a record by its exact fingerprint.
    func lookup(fingerprint: Fingerprint) async -> TrustedDeviceRecord?
    /// Adds a new trusted device. Fails (returns `false`) if `maxTrustedDevicesPerHost` (spec
    /// §7.6, §11.3: 20) is already reached and no existing record shares this fingerprint.
    @discardableResult
    func add(_ record: TrustedDeviceRecord) async -> Bool
    /// Marks a fingerprint's record `revoked = true` (spec §3.2.6: does not delete the record).
    func revoke(fingerprint: Fingerprint) async
    /// Updates `lastSeen` for a fingerprint's record, if present.
    func updateLastSeen(fingerprint: Fingerprint, date: Date) async
    /// Replaces an existing record wholesale (e.g. renaming, toggling `allowScripts`).
    func update(_ record: TrustedDeviceRecord) async
    /// Removes a record entirely (spec §3.2.4: "Forget device").
    func remove(fingerprint: Fingerprint) async
}
