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
        try loadIdentityWithTier(label: label)?.identity
    }

    /// Looks up `label` across both keychain tiers — `.dataProtection` first, `.legacyNoPrompt`
    /// second — reporting which one it was found in (REQUIRED FIX 1/3: callers use this to decide
    /// whether a migration is needed). A failure on the `.dataProtection` probe (e.g.
    /// `errSecMissingEntitlement` in an unsigned/ad-hoc/CI/test process) is treated the same as "not
    /// found there" rather than a hard error, so the legacy-tier probe still runs; only a genuinely
    /// unexpected failure on the *last* tier tried is thrown.
    public func loadIdentityWithTier(label: String) throws -> (identity: SecIdentity, tier: IdentityStoreTier)? {
        if let identity = try? queryIdentity(label: label, useDataProtectionKeychain: true) {
            return (identity, .dataProtection)
        }
        if let identity = try queryIdentity(label: label, useDataProtectionKeychain: false) {
            return (identity, .legacyNoPrompt)
        }
        return nil
    }

    private func queryIdentity(label: String, useDataProtectionKeychain: Bool) throws -> SecIdentity? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassIdentity,
            kSecAttrLabel: label,
            kSecReturnRef: true,
            kSecUseDataProtectionKeychain: useDataProtectionKeychain,
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
        if case .usable = signingProbe(identity, timeout: timeout) { return true }
        return false
    }

    /// The detailed form of `canSign`: *why* an identity's private key can't produce a signature.
    /// The two failure modes need completely different responses and are otherwise indistinguishable
    /// (both just stall the TLS handshake), so callers — and on-device diagnostics, which have no OS
    /// log access — need them told apart:
    ///
    /// - `.signingFailed` is a synchronous refusal (`SecKeyCreateSignature` returned an error). The
    ///   key is present but unusable for this algorithm.
    /// - `.blocked` means the call never returned at all within `timeout` — the ACL-prompt case on
    ///   macOS, and (empirically, on a real iPhone) a Data-Protection key whose access control the
    ///   current process can't satisfy without an authentication context.
    public func signingProbe(_ identity: SecIdentity, timeout: TimeInterval = 2.0) -> SigningProbe {
        var privateKey: SecKey?
        let status = SecIdentityCopyPrivateKey(identity, &privateKey)
        guard status == errSecSuccess, let privateKey else {
            return .noPrivateKey(status: status)
        }
        let semaphore = DispatchSemaphore(value: 0)
        let box = SignatureProbeResult()
        // `SecKey` isn't `Sendable`, but Security.framework's CF types are safe to hand across threads
        // as opaque handles (same rationale as `GeneratedIdentity.secIdentity` — see its header comment)
        // — `nonisolated(unsafe)` documents that at the capture instead of silencing it file-wide.
        nonisolated(unsafe) let keyForProbeThread = privateKey
        let thread = Thread {
            var error: Unmanaged<CFError>?
            let payload = Data("aircontrol-identity-probe".utf8) as CFData
            let signature = SecKeyCreateSignature(keyForProbeThread, .ecdsaSignatureMessageX962SHA256, payload, &error)
            if signature != nil {
                box.set(.usable)
            } else {
                box.set(.signingFailed(description: error.map { String(describing: $0.takeRetainedValue()) } ?? "unknown"))
            }
            semaphore.signal()
        }
        thread.qualityOfService = .userInitiated
        thread.start()
        guard semaphore.wait(timeout: .now() + timeout) == .success else { return .blocked }
        return box.value
    }

    /// REQUIRED FIX 3: if `label` currently resolves to an identity in the legacy keychain tier *and*
    /// this process's signature is already proven trusted by that identity's ACL (`canSign`, so
    /// exporting the same key's raw representation carries no ACL-prompt risk — export needs the same
    /// "extract" authorization signing does), re-adds the *same* key and certificate to the Data
    /// Protection keychain and deletes the legacy copy. The certificate — and therefore the host
    /// fingerprint every paired phone has pinned — is untouched, so nothing needs to re-pair.
    ///
    /// Returns `nil` (never throws) whenever migration isn't applicable or isn't safe: no legacy item,
    /// already on the Data Protection tier, the ACL wouldn't currently let this process touch the key
    /// without prompting, or any step of the export/re-add fails. Callers fall back to their existing
    /// replace-on-unusable path in all of those cases — see `IdentityMigrationDecision` for the same
    /// logic pulled out into a pure, unit-testable form.
    public func migrateLegacyIdentityIfPossible(label: String) -> GeneratedIdentity? {
        guard let found = try? loadIdentityWithTier(label: label), found.tier == .legacyNoPrompt else { return nil }
        guard canSign(found.identity) else { return nil }

        var certificateRef: SecCertificate?
        guard SecIdentityCopyCertificate(found.identity, &certificateRef) == errSecSuccess, let certificate = certificateRef else {
            return nil
        }
        var privateKeyRef: SecKey?
        guard SecIdentityCopyPrivateKey(found.identity, &privateKeyRef) == errSecSuccess, let privateKey = privateKeyRef else {
            return nil
        }
        var exportError: Unmanaged<CFError>?
        guard let rawPrivateKey = SecKeyCopyExternalRepresentation(privateKey, &exportError) as Data? else {
            return nil
        }

        guard let migrated = try? IdentityFactory.reimportMigratedIdentity(
            rawPrivateKey: rawPrivateKey,
            certificate: certificate,
            label: label
        ) else { return nil }

        // Best-effort: the migrated copy is already persisted and usable even if this cleanup fails,
        // so a failure here doesn't undo the migration — it just leaves a stale legacy-tier item
        // behind for the next run to find (and no-op on, since `loadIdentityWithTier` now finds the
        // `.dataProtection` copy first).
        try? IdentityFactory.deleteIdentity(label: label, useDataProtectionKeychain: false)
        return migrated
    }
}

/// Outcome of `KeychainIdentityStore.signingProbe` — see its doc comment.
public enum SigningProbe: Sendable, Equatable {
    /// The key produced a signature: safe to hand to the TLS stack.
    case usable
    /// The identity carries no usable private key at all (`SecIdentityCopyPrivateKey` failed).
    case noPrivateKey(status: OSStatus)
    /// `SecKeyCreateSignature` returned an error. `description` is the `CFError`'s own text.
    case signingFailed(description: String)
    /// `SecKeyCreateSignature` never returned within the probe's timeout (an ACL/authentication
    /// prompt nobody can answer) — the failure mode that stalls a TLS handshake outright.
    case blocked

    /// A short, log-safe rendering (no key material is ever involved in any case's payload).
    public var summary: String {
        switch self {
        case .usable: return "usable"
        case .noPrivateKey(let status): return "no-private-key(\(status))"
        case .signingFailed(let description): return "signing-failed(\(description))"
        case .blocked: return "blocked"
        }
    }
}

private final class SignatureProbeResult: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: SigningProbe = .blocked
    var value: SigningProbe { lock.lock(); defer { lock.unlock() }; return stored }
    func set(_ newValue: SigningProbe) { lock.lock(); stored = newValue; lock.unlock() }
}
