// Services/KeychainStore/KeychainStore.swift
// Generic Keychain wrapper per arch §6.1. Stores raw `Data` by (service, account); the actual
// Secure-Enclave identity generation and certificate management (arch §3.2 `KeychainStore`
// bullet) belongs to the Connection/Pairing agents, who should build on top of this generic
// get/set/delete rather than calling `Security` directly, so every Keychain access in the app
// shares one attribute policy.
//
// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (arch §6.1) is used for every item written
// through this store — items are never synced to iCloud Keychain and are unavailable before
// first unlock, matching "never exported" for the client identity key.

import Foundation
import Security

/// A Keychain-stored item's coordinates. `KeychainKey` below defines the fixed items from arch
/// §6.1; ad-hoc callers may still construct their own for one-off items (e.g. per-host records).
public struct KeychainItem: Sendable, Hashable {
    public let service: String
    public let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }
}

/// Errors surfaced by `KeychainStore` operations.
public enum KeychainStoreError: Error, Sendable, Equatable {
    case unhandled(OSStatus)
}

/// Generic Keychain get/set/delete of `Data`, scoped to `kSecClassGenericPassword` with
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Certificate/key items (`kSecClassCertificate`,
/// `kSecClassKey`) used for identities and trusted-host certs are a different `SecItem` class and
/// are out of this protocol's scope — they belong to whichever agent implements `IdentityFactory`
/// / `TrustedCertificateStore` (arch §3.2), which may still use `KeychainItem` naming conventions
/// from `KeychainKey` for consistency.
public protocol KeychainStore: Sendable {
    func set(_ data: Data, for item: KeychainItem) throws
    func get(_ item: KeychainItem) throws -> Data?
    func delete(_ item: KeychainItem) throws
}

/// `Security` framework-backed implementation.
public struct SecureKeychainStore: KeychainStore {
    public init() {}

    public func set(_ data: Data, for item: KeychainItem) throws {
        try delete(item)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: item.service,
            kSecAttrAccount: item.account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainStoreError.unhandled(status) }
    }

    public func get(_ item: KeychainItem) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: item.service,
            kSecAttrAccount: item.account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainStoreError.unhandled(status) }
        return result as? Data
    }

    public func delete(_ item: KeychainItem) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: item.service,
            kSecAttrAccount: item.account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unhandled(status)
        }
    }
}

/// In-memory stand-in for previews, tests, and default DI wiring before a real identity/trust
/// implementation is wired in.
public final class InMemoryKeychainStore: KeychainStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [KeychainItem: Data] = [:]

    public init() {}

    public func set(_ data: Data, for item: KeychainItem) throws {
        lock.lock(); defer { lock.unlock() }
        storage[item] = data
    }

    public func get(_ item: KeychainItem) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[item]
    }

    public func delete(_ item: KeychainItem) throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: item)
    }
}

/// Item keys from arch §6.1's "iOS" rows. Certificate labels are not simple (service, account)
/// pairs in the `SecItem` sense (they're looked up by label within `kSecClassCertificate`), but
/// are listed here as constants so every caller uses the same literal strings.
public enum KeychainKey {
    /// `kSecClassKey`, P-256, Secure Enclave when available, `kSecAttrApplicationTag`.
    public static let clientIdentityKeyTag = "com.airmouse.app.identity"
    /// `kSecClassCertificate` label for the client's own identity certificate.
    public static let clientIdentityCertificateLabel = "AirMouse Client Identity"
    /// `kSecClassCertificate` label prefix for a trusted host's certificate; the full label is
    /// `"\(trustedHostCertificateLabelPrefix)\(hostID base64url)"`.
    public static let trustedHostCertificateLabelPrefix = "AirMouse Trusted Host "
}
