import Security

/// Persistence for a device's own `SecIdentity` (not to be confused with the *trusted-peer* store —
/// spec §3.2.4's `TrustedDevices.json`/`TrustedHosts.json` plus Keychain certificates — which is a much
/// richer, app-owned model (`hostID`/`clientID`, `name`, `model`, `firstPaired`, `lastSeen`, etc.) that
/// arch's public API table assigns to the apps, not to this module).
///
/// This is intentionally minimal (per this module's task brief: "implementation of Keychain persistence
/// can be minimal here; apps will wrap it"): just enough to look an identity back up by the label
/// `IdentityFactory` stored it under, and to remove it (spec §7.3: "Reset identity" in
/// Preferences/Settings "revokes all devices" / "uninstall / reset").
public protocol IdentityStore: Sendable {
    /// Looks up a previously-created identity by its Keychain label. Returns `nil` if none exists.
    func loadIdentity(label: String) throws -> SecIdentity?

    /// Removes the identity (key + certificate) stored under `label`.
    func deleteIdentity(label: String) throws
}

/// The minimal Keychain-backed `IdentityStore`. Apps are expected to wrap this with their own
/// higher-level "the device's identity" concept (first-launch generation, label naming, etc.).
public struct KeychainIdentityStore: IdentityStore {
    public init() {}

    public func loadIdentity(label: String) throws -> SecIdentity? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassIdentity,
            kSecAttrLabel: label,
            kSecReturnRef: true,
            kSecUseDataProtectionKeychain: false,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let identity = result else { return nil }
            return (identity as! SecIdentity) // swift(unsafe): guaranteed by kSecClassIdentity above
        case errSecItemNotFound:
            return nil
        default:
            throw IdentityFactoryError.identityLookupFailed(status: status)
        }
    }

    public func deleteIdentity(label: String) throws {
        try IdentityFactory.deleteIdentity(label: label)
    }
}
