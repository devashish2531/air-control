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

import Foundation

extension KeychainIdentityStore {
    /// Proves the identity's private key can sign *without blocking on a Keychain ACL prompt*.
    ///
    /// A legacy-keychain key's ACL trusts the code signature of the process that created it. When the
    /// app is rebuilt with a different signature (ad-hoc → team-signed, or any ad-hoc rebuild), macOS
    /// routes `SecKeyCreateSignature` through a `SecurityAgent` prompt that a menu-bar helper or a
    /// headless run never gets to answer — the TLS handshake then stalls forever while signing the
    /// server's CertificateVerify. This runs one throwaway signature on a background thread and gives up
    /// after `timeout`; callers treat `false` as "stale identity: delete and mint a fresh one".
    public func canSign(_ identity: SecIdentity, timeout: TimeInterval = 2.0) -> Bool {
        var privateKey: SecKey?
        guard SecIdentityCopyPrivateKey(identity, &privateKey) == errSecSuccess, let privateKey else { return false }
        let semaphore = DispatchSemaphore(value: 0)
        let box = SignatureProbeResult()
        let thread = Thread {
            var error: Unmanaged<CFError>?
            let payload = Data("airmouse-identity-probe".utf8) as CFData
            let signature = SecKeyCreateSignature(privateKey, .ecdsaSignatureMessageX962SHA256, payload, &error)
            box.set(signature != nil)
            semaphore.signal()
        }
        thread.qualityOfService = .userInitiated
        thread.start()
        guard semaphore.wait(timeout: .now() + timeout) == .success else { return false }
        return box.value
    }
}

private final class SignatureProbeResult: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return stored }
    func set(_ newValue: Bool) { lock.lock(); stored = newValue; lock.unlock() }
}
