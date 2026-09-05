import CryptoKit
import Security
import X509
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Builds a `SecIdentity` (certificate + matching private key, importable into
/// `sec_protocol_options_set_local_identity`) per spec §7.1:
///
/// > Security.framework has no public certificate-minting API, so identities are built in
/// > `AirMouseCrypto.IdentityFactory`.
///
/// **Known risk (arch §7.1, spike R-1) and how this implementation mitigates it.** Arch §7.1 describes
/// pairing a certificate with its private key via `SecIdentityCreateWithCertificate`, which searches a
/// Keychain for a private key whose public half matches the certificate — "the most fiddly
/// security-critical piece", per arch, precisely because that search can fail to find a key that is
/// genuinely present (platform/version-dependent). Two things changed that plan here:
///
/// 1. `SecIdentityCreateWithCertificate` is **macOS-only** (`Security/SecIdentity.h` guards it with
///    `#if SEC_OS_OSX`); it does not exist on iOS at all, so `AirMouseCrypto` cannot build for the iOS
///    Simulator/device against it.
/// 2. Both platforms instead expose `SecIdentityCreate(allocator:certificate:privateKey:)`
///    (`API_AVAILABLE(macos(10.12), ios(11.2), ...)`), which pairs a `SecCertificate` and `SecKey`
///    **directly**, with no Keychain search at all — it "returns null if the private key does not
///    correspond to the public key in the certificate" and nothing else. This is both the fix for the
///    iOS build and a strictly better fit for arch §7.1's risk: there is no search to fail.
///
/// This implementation therefore always builds the returned `SecIdentity` via `SecIdentityCreate`, on
/// both platforms, from whichever `SecKey` the two paths below produce:
///
/// - **Path A** (preferred, `makeIdentity`): `SecKeyCreateRandomKey` generates the private key directly
///   in the Keychain (optionally in the Secure Enclave on iOS) so it survives across launches; the
///   certificate is *also* persisted (`SecItemAdd(kSecClassCertificate, ...)`) so a later
///   `IdentityStore.loadIdentity(label:)` — a plain `SecItemCopyMatching(kSecClassIdentity, ...)` query,
///   the ordinary Keychain-Services matching path, unrelated to `SecIdentityCreateWithCertificate` — can
///   still find both and rebuild the identity in a future process.
/// - **Path B** (fallback, used whenever Path A's key generation fails, e.g. Secure Enclave requested
///   but unavailable): a software `P256.Signing.PrivateKey` is generated with CryptoKit and imported as
///   a permanent Keychain `SecKey` (`SecKeyCreateWithData` + `SecItemAdd`) the same way, so it is
///   discoverable the same way on a later launch.
/// - **`makeEphemeralIdentity`** (the in-memory/test path): builds a transient `SecKey` and
///   `SecCertificate` that are never added to the Keychain at all, then pairs them with
///   `SecIdentityCreate`. This is possible precisely because of point 2 above — it did not require a
///   fallback like PKCS#12 import, since `SecIdentityCreate` was already keychain-free.
public enum IdentityFactory: Sendable {
    /// Generates (Path A, or Path B fallback) a private key and certificate, persists both to the
    /// Keychain under `label` (so a later `IdentityStore.loadIdentity(label:)` can find them again),
    /// and returns the resulting `SecIdentity`.
    ///
    /// - Parameters:
    ///   - commonName: certificate CN, e.g. `"AirMouse Host <hostID b64u>"` (spec §3.2.1).
    ///   - label: Keychain label shared by the key and certificate items.
    ///   - preferSecureEnclave: whether to attempt Secure Enclave key generation first (spec §3.2.1:
    ///     client "in Secure Enclave when available", host "kSecAttrTokenID none" — callers pass
    ///     `false` for the host identity).
    ///   - accessibility: the `kSecAttrAccessible*` constant for the private key (spec §3.2.1:
    ///     `kSecAttrAccessibleAfterFirstUnlock` for the host, `...ThisDeviceOnly` for the client).
    ///   - validityDuration: certificate validity (spec §3.2.1: 10 years, `CertificateBuilder.defaultValidityDuration`).
    public static func makeIdentity(
        commonName: String,
        label: String,
        preferSecureEnclave: Bool,
        accessibility: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        validityDuration: TimeInterval = CertificateBuilder.defaultValidityDuration
    ) throws -> GeneratedIdentity {
        let (secKey, backing, tier) = try makeOrImportPrivateKey(
            label: label,
            preferSecureEnclave: preferSecureEnclave,
            accessibility: accessibility
        )
        let (output, secCertificate) = try buildCertificate(
            signingKey: secKey,
            commonName: commonName,
            validityDuration: validityDuration
        )

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: secCertificate,
            kSecAttrLabel: label,
            kSecUseDataProtectionKeychain: tier == .dataProtection,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw IdentityFactoryError.certificatePersistenceFailed(status: addStatus)
        }

        let identity = try makeSecIdentity(certificate: secCertificate, privateKey: secKey)
        return GeneratedIdentity(
            secIdentity: identity,
            certificateDER: output.der,
            fingerprint: output.fingerprint,
            backing: backing,
            label: label,
            tier: tier
        )
    }

    /// The in-memory/test path: a transient software CryptoKit key and a transient certificate, neither
    /// ever added to the Keychain (see type header, point 2) — no Keychain access at all is required,
    /// so this cannot fail in a sandboxed test environment the way `makeIdentity` can.
    public static func makeEphemeralIdentity(
        commonName: String,
        label: String = "AirMouseCrypto.ephemeral.\(UUID().uuidString)"
    ) throws -> GeneratedIdentity {
        let privateKey = P256.Signing.PrivateKey()
        let softwareSecKey = try makeTransientSecKey(privateKey)
        let (output, secCertificate) = try buildCertificate(
            signingKey: softwareSecKey,
            commonName: commonName,
            validityDuration: CertificateBuilder.defaultValidityDuration
        )
        let identity = try makeSecIdentity(certificate: secCertificate, privateKey: softwareSecKey)
        return GeneratedIdentity(
            secIdentity: identity,
            certificateDER: output.der,
            fingerprint: output.fingerprint,
            backing: .software,
            label: label
        )
    }

    /// Removes every Keychain item (key and certificate) stored under `label`, in *every* tier
    /// (`IdentityStoreTier.dataProtection` and `.legacyNoPrompt` — a label may live in either,
    /// depending on which tier `makeIdentity` landed on or migrated to). Best-effort: does not throw
    /// merely because a tier had nothing to delete, or because this process can't use a given tier at
    /// all (`errSecMissingEntitlement` — e.g. an unsigned build has no Data Protection keychain access
    /// whatsoever, so there's nothing there to fail to delete). A no-op for identities produced by
    /// `makeEphemeralIdentity`, which never touch the Keychain. Spec §7.3's "Reset identity" needs
    /// this to actually nuke whichever tier the identity currently lives in.
    public static func deleteIdentity(label: String) throws {
        var lastError: IdentityFactoryError?
        for useDataProtectionKeychain in [true, false] {
            do {
                try deleteIdentity(label: label, useDataProtectionKeychain: useDataProtectionKeychain)
            } catch let error as IdentityFactoryError {
                lastError = error
            }
        }
        if let lastError { throw lastError }
    }

    /// Single-tier variant, used both by the public `deleteIdentity(label:)` above and by
    /// `KeychainIdentityStore.migrateLegacyIdentityIfPossible`, which must delete *only* the legacy
    /// copy once the Data Protection copy is confirmed persisted (not the item it just created).
    static func deleteIdentity(label: String, useDataProtectionKeychain: Bool) throws {
        for keyClass in [kSecClassKey, kSecClassCertificate, kSecClassIdentity] {
            let query: [CFString: Any] = [
                kSecClass: keyClass,
                kSecAttrLabel: label,
                kSecUseDataProtectionKeychain: useDataProtectionKeychain,
            ]
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound || status == errSecMissingEntitlement else {
                throw IdentityFactoryError.deletionFailed(status: status)
            }
        }
    }

    // MARK: - SecIdentity construction (both platforms — see type header, point 2)

    /// Pairs `certificate` and `privateKey` directly via `SecIdentityCreate`, with no Keychain search
    /// (available on both iOS 11.2+ and macOS 10.12+, unlike the macOS-only `SecIdentityCreateWithCertificate`).
    private static func makeSecIdentity(certificate: SecCertificate, privateKey: SecKey) throws -> SecIdentity {
        guard let identity = SecIdentityCreate(nil, certificate, privateKey) else {
            throw IdentityFactoryError.identityLookupFailed(status: errSecParam)
        }
        return identity
    }

    // MARK: - Shared: public key export → self-signed certificate → SecCertificate

    private static func buildCertificate(
        signingKey secKey: SecKey,
        commonName: String,
        validityDuration: TimeInterval
    ) throws -> (CertificateBuilder.Output, SecCertificate) {
        let publicKey = try exportPublicKey(from: secKey)
        let signingKey = try Certificate.PrivateKey(secKey)

        let output: CertificateBuilder.Output
        do {
            output = try CertificateBuilder.makeSelfSigned(
                publicKey: publicKey,
                signingKey: signingKey,
                commonName: commonName,
                validityDuration: validityDuration
            )
        } catch {
            throw IdentityFactoryError.publicKeyExportFailed(description: String(describing: error))
        }

        guard let secCertificate = SecCertificateCreateWithData(nil, output.der as CFData) else {
            throw IdentityFactoryError.certificateImportFailed
        }
        return (output, secCertificate)
    }

    // MARK: - Path A: Keychain (optionally Secure Enclave) key generation, tiered

    /// Tries `IdentityStoreTier.dataProtection` first; on macOS, if that fails for *any* reason (in
    /// practice: `errSecMissingEntitlement`/-34018, since this process's signed app lacks
    /// `com.apple.application-identifier` — unsigned/ad-hoc/CI/test builds, every time), falls back to
    /// `.legacyNoPrompt`. iOS has no legacy-keychain concept and always has Data Protection keychain
    /// access, so a `.dataProtection` failure there just propagates (callers already have their own
    /// ephemeral fallback, e.g. `ConnectionFeature.loadOrCreateClientIdentity`).
    private static func makeOrImportPrivateKey(
        label: String,
        preferSecureEnclave: Bool,
        accessibility: CFString
    ) throws -> (SecKey, IdentityBackingKind, IdentityStoreTier) {
        do {
            let (key, backing) = try makeOrImportPrivateKey(
                tier: .dataProtection,
                label: label,
                preferSecureEnclave: preferSecureEnclave,
                accessibility: accessibility
            )
            return (key, backing, .dataProtection)
        } catch {
            #if os(macOS)
            let (key, backing) = try makeOrImportPrivateKey(
                tier: .legacyNoPrompt,
                label: label,
                preferSecureEnclave: preferSecureEnclave,
                accessibility: accessibility
            )
            return (key, backing, .legacyNoPrompt)
            #else
            throw error
            #endif
        }
    }

    private static func makeOrImportPrivateKey(
        tier: IdentityStoreTier,
        label: String,
        preferSecureEnclave: Bool,
        accessibility: CFString
    ) throws -> (SecKey, IdentityBackingKind) {
        guard tier == .dataProtection else {
            // `.legacyNoPrompt` deliberately never attempts native generation (the `SecKeyCreateRandomKey`
            // call below) at all — see this function's doc comment: a key *natively* generated in the
            // legacy keychain comes back as an old CDSA-backed `SecKey` that the modern
            // `SecKeyCreateSignature`/`SecKeyAlgorithm` API (what the TLS handshake and `canSign` both
            // use) cannot sign with (`errSecParam`/-50, "algorithm not supported by the key") — a hard,
            // unconditional incompatibility, not a prompt/ACL issue, and not something that shows up
            // until the first real signature attempt. Importing a software CryptoKit key (Path B)
            // instead always yields a modern `SecKey` wrapper, so this tier goes straight there.
            let softwareKey = try importSoftwarePrivateKey(
                P256.Signing.PrivateKey(),
                tier: tier,
                label: label,
                accessibility: accessibility
            )
            return (softwareKey, .software)
        }

        var attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecAttrIsPermanent: true,
            kSecAttrLabel: label,
            kSecAttrApplicationTag: Data(label.utf8),
            kSecAttrSynchronizable: false,
            kSecUseDataProtectionKeychain: true,
            kSecPrivateKeyAttrs: try privateKeyAttrs(tier: tier, label: label, accessibility: accessibility),
        ]

        #if os(iOS)
        if preferSecureEnclave {
            attributes[kSecAttrTokenID] = kSecAttrTokenIDSecureEnclave
        }
        #endif

        var error: Unmanaged<CFError>?
        if let secKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) {
            #if os(iOS)
            return (secKey, preferSecureEnclave ? .secureEnclave : .keychainSecKey)
            #else
            return (secKey, .keychainSecKey)
            #endif
        }

        #if os(iOS)
        if preferSecureEnclave {
            // Some iOS versions/devices reject Secure Enclave key generation for this attribute
            // combination; retry as a plain (still hardware-Keychain-generated) key first.
            return try makeOrImportPrivateKey(tier: tier, label: label, preferSecureEnclave: false, accessibility: accessibility)
        }
        #endif

        // Path B per arch §7.1: `SecKeyCreateRandomKey` itself failed (not just a Secure Enclave
        // preference) — fall back to a software CryptoKit key imported into the Keychain, recorded as
        // `.software` so callers can surface it in diagnostics (spec §7.1: "recorded in
        // hostState/diagnostics as identity: software").
        let softwareKey = try importSoftwarePrivateKey(
            P256.Signing.PrivateKey(),
            tier: tier,
            label: label,
            accessibility: accessibility
        )
        return (softwareKey, .software)
    }

    /// Builds the `kSecPrivateKeyAttrs` sub-dictionary for native (`SecKeyCreateRandomKey`) key
    /// generation — reachable only for `.dataProtection` (see the caller: `.legacyNoPrompt` never
    /// generates natively at all, only imports a software key — `importSoftwarePrivateKey` builds its
    /// own, differently-shaped attributes directly). Uses the modern `kSecAttrAccessControl`
    /// (a `SecAccessControl`), required alongside `kSecUseDataProtectionKeychain: true`.
    private static func privateKeyAttrs(tier: IdentityStoreTier, label: String, accessibility: CFString) throws -> [CFString: Any] {
        precondition(tier == .dataProtection, "native key generation is only attempted for .dataProtection")
        var accessControlError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(nil, accessibility, [], &accessControlError) else {
            throw IdentityFactoryError.accessControlCreationFailed(
                description: accessControlError.map { String(describing: $0.takeRetainedValue()) } ?? "unknown"
            )
        }
        return [kSecAttrAccessControl: accessControl]
    }

    #if os(macOS)
    /// REQUIRED FIX 2: builds a `SecAccess` whose ACL entries are opened to *any* application
    /// (`SecACLSetContents(acl, applicationList: nil, ...)` — per `Security/SecACL.h`, a `nil`
    /// application list means no per-application restriction, so macOS never routes access through a
    /// `SecurityAgent` confirmation prompt for it), instead of `SecAccessCreate`'s own default ACL
    /// (which trusts only the *creating* process's code signature — that default is exactly today's
    /// defect: any rebuild with a different signature breaks it).
    ///
    /// `SecAccess`/`SecACL` (`SecAccessCreate`, `SecAccessCopyACLList`, `SecACLSetContents`) are all
    /// `API_DEPRECATED("SecKeychain is deprecated", macos(10.2/10.3/10.7, 10.10))` — deliberately used
    /// anyway, since there is no non-deprecated public API for a legacy-keychain ACL with no
    /// per-application restriction. The actual calls are isolated in a nested, `@available`-marked
    /// helper so *that* deprecation warning is silenced only for these specific calls, without making
    /// `makeNoPromptAccess` itself deprecated (which would otherwise cascade the warning to every
    /// caller, all the way up to the public `makeIdentity` API).
    private static func makeNoPromptAccess(label: String) throws -> SecAccess {
        @available(macOS, deprecated: 10.10, message: "SecAccess/SecACL: no replacement exists for a legacy-keychain \"any application, no prompt\" ACL")
        func createNoPromptAccess() throws -> SecAccess {
            var access: SecAccess?
            let createStatus = SecAccessCreate(label as CFString, nil, &access)
            guard createStatus == errSecSuccess, let access else {
                throw IdentityFactoryError.accessControlCreationFailed(description: "SecAccessCreate failed: status \(createStatus)")
            }
            var aclListRef: CFArray?
            let listStatus = SecAccessCopyACLList(access, &aclListRef)
            guard listStatus == errSecSuccess, let aclList = aclListRef as? [SecACL] else {
                throw IdentityFactoryError.accessControlCreationFailed(description: "SecAccessCopyACLList failed: status \(listStatus)")
            }
            for acl in aclList {
                let contentsStatus = SecACLSetContents(acl, nil, label as CFString, SecKeychainPromptSelector(rawValue: 0))
                guard contentsStatus == errSecSuccess else {
                    throw IdentityFactoryError.accessControlCreationFailed(description: "SecACLSetContents failed: status \(contentsStatus)")
                }
            }
            return access
        }
        return try createNoPromptAccess()
    }
    #endif

    // MARK: - Path B (persistent variant): import a software CryptoKit key into the Keychain

    private static func importSoftwarePrivateKey(
        _ privateKey: P256.Signing.PrivateKey,
        tier: IdentityStoreTier,
        label: String,
        accessibility: CFString
    ) throws -> SecKey {
        let secKey = try makeTransientSecKey(privateKey)

        var addQuery: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecValueRef: secKey,
            kSecAttrLabel: label,
            kSecAttrApplicationTag: Data(label.utf8),
            kSecAttrSynchronizable: false,
            kSecUseDataProtectionKeychain: tier == .dataProtection,
        ]
        switch tier {
        case .dataProtection:
            var accessControlError: Unmanaged<CFError>?
            guard let accessControl = SecAccessControlCreateWithFlags(nil, accessibility, [], &accessControlError) else {
                throw IdentityFactoryError.accessControlCreationFailed(
                    description: accessControlError.map { String(describing: $0.takeRetainedValue()) } ?? "unknown"
                )
            }
            addQuery[kSecAttrAccessControl] = accessControl
        case .legacyNoPrompt:
            #if os(macOS)
            addQuery[kSecAttrAccessible] = accessibility
            addQuery[kSecAttrAccess] = try makeNoPromptAccess(label: label)
            #else
            throw IdentityFactoryError.accessControlCreationFailed(description: "legacyNoPrompt tier is macOS-only")
            #endif
        case .ephemeral:
            throw IdentityFactoryError.accessControlCreationFailed(description: "ephemeral identities never persist a private key")
        }

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw IdentityFactoryError.keyPersistenceFailed(status: addStatus)
        }

        return secKey
    }

    // MARK: - Migration (REQUIRED FIX 3): re-import an existing key/certificate into the Data
    // Protection keychain, keeping the same key material so the fingerprint doesn't change.

    /// Persists `rawPrivateKey` (an X9.63 P-256 private-key export) and `certificate` — both already
    /// known-good, exported from a legacy-tier identity by `KeychainIdentityStore
    /// .migrateLegacyIdentityIfPossible` — into the Data Protection keychain under `label`, and builds
    /// the resulting `SecIdentity`/`GeneratedIdentity`. Not `public`: this is only ever called
    /// immediately after an export whose safety (no ACL prompt) the caller already established via
    /// `canSign`.
    static func reimportMigratedIdentity(rawPrivateKey: Data, certificate: SecCertificate, label: String) throws -> GeneratedIdentity {
        let creationAttributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits: 256,
        ]
        var keyImportError: Unmanaged<CFError>?
        guard let transientKey = SecKeyCreateWithData(rawPrivateKey as CFData, creationAttributes as CFDictionary, &keyImportError) else {
            throw IdentityFactoryError.keyImportFailed(
                description: keyImportError.map { String(describing: $0.takeRetainedValue()) } ?? "unknown"
            )
        }

        var accessControlError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, [], &accessControlError
        ) else {
            throw IdentityFactoryError.accessControlCreationFailed(
                description: accessControlError.map { String(describing: $0.takeRetainedValue()) } ?? "unknown"
            )
        }
        let keyAddQuery: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecValueRef: transientKey,
            kSecAttrLabel: label,
            kSecAttrApplicationTag: Data(label.utf8),
            kSecAttrSynchronizable: false,
            kSecAttrAccessControl: accessControl,
            kSecUseDataProtectionKeychain: true,
        ]
        let keyAddStatus = SecItemAdd(keyAddQuery as CFDictionary, nil)
        guard keyAddStatus == errSecSuccess || keyAddStatus == errSecDuplicateItem else {
            throw IdentityFactoryError.keyPersistenceFailed(status: keyAddStatus)
        }

        let certAddQuery: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: certificate,
            kSecAttrLabel: label,
            kSecUseDataProtectionKeychain: true,
        ]
        let certAddStatus = SecItemAdd(certAddQuery as CFDictionary, nil)
        guard certAddStatus == errSecSuccess || certAddStatus == errSecDuplicateItem else {
            throw IdentityFactoryError.certificatePersistenceFailed(status: certAddStatus)
        }

        let der = SecCertificateCopyData(certificate) as Data
        let identity = try makeSecIdentity(certificate: certificate, privateKey: transientKey)
        return GeneratedIdentity(
            secIdentity: identity,
            certificateDER: der,
            fingerprint: Fingerprint(certificateDER: der),
            backing: .keychainSecKey,
            label: label,
            tier: .dataProtection
        )
    }

    /// Wraps a software CryptoKit private key as a transient (not Keychain-persisted) `SecKey`, usable
    /// directly with `SecIdentityCreate`.
    private static func makeTransientSecKey(_ privateKey: P256.Signing.PrivateKey) throws -> SecKey {
        let creationAttributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits: 256,
        ]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(
            privateKey.x963Representation as CFData,
            creationAttributes as CFDictionary,
            &error
        ) else {
            throw IdentityFactoryError.keyImportFailed(
                description: error.map { String(describing: $0.takeRetainedValue()) } ?? "unknown"
            )
        }
        return secKey
    }

    // MARK: - Public key export (spec §7.1 step 2: "SecKeyCopyExternalRepresentation, X9.63")

    static func exportPublicKey(from secKey: SecKey) throws -> P256.Signing.PublicKey {
        guard let publicSecKey = SecKeyCopyPublicKey(secKey) else {
            throw IdentityFactoryError.publicKeyExportFailed(description: "SecKeyCopyPublicKey returned nil")
        }
        var error: Unmanaged<CFError>?
        guard let representation = SecKeyCopyExternalRepresentation(publicSecKey, &error) as Data? else {
            throw IdentityFactoryError.publicKeyExportFailed(
                description: error.map { String(describing: $0.takeRetainedValue()) } ?? "unknown"
            )
        }
        guard let publicKey = try? P256.Signing.PublicKey(x963Representation: representation) else {
            throw IdentityFactoryError.publicKeyParseFailed
        }
        return publicKey
    }
}
