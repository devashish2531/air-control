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
        let (secKey, backing) = try makeOrImportPrivateKey(
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
            kSecUseDataProtectionKeychain: false,
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
            label: label
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

    /// Removes every Keychain item (key and certificate) stored under `label`. Best-effort: does not
    /// throw if nothing was found. A no-op for identities produced by `makeEphemeralIdentity`, which
    /// never touch the Keychain.
    public static func deleteIdentity(label: String) throws {
        for keyClass in [kSecClassKey, kSecClassCertificate, kSecClassIdentity] {
            let query: [CFString: Any] = [
                kSecClass: keyClass,
                kSecAttrLabel: label,
                kSecUseDataProtectionKeychain: false,
            ]
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
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

    // MARK: - Path A: Keychain (optionally Secure Enclave) key generation

    private static func makeOrImportPrivateKey(
        label: String,
        preferSecureEnclave: Bool,
        accessibility: CFString
    ) throws -> (SecKey, IdentityBackingKind) {
        var accessControlError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(nil, accessibility, [], &accessControlError) else {
            throw IdentityFactoryError.accessControlCreationFailed(
                description: accessControlError.map { String(describing: $0.takeRetainedValue()) } ?? "unknown"
            )
        }

        var attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecAttrIsPermanent: true,
            kSecAttrLabel: label,
            kSecAttrApplicationTag: Data(label.utf8),
            kSecUseDataProtectionKeychain: false,
            kSecPrivateKeyAttrs: [kSecAttrAccessControl: accessControl] as [CFString: Any],
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
            return try makeOrImportPrivateKey(label: label, preferSecureEnclave: false, accessibility: accessibility)
        }
        #endif

        // Path B per arch §7.1: `SecKeyCreateRandomKey` itself failed (not just a Secure Enclave
        // preference) — fall back to a software CryptoKit key imported into the Keychain, recorded as
        // `.software` so callers can surface it in diagnostics (spec §7.1: "recorded in
        // hostState/diagnostics as identity: software").
        let softwareKey = try importSoftwarePrivateKey(
            P256.Signing.PrivateKey(),
            label: label,
            accessibility: accessibility
        )
        return (softwareKey, .software)
    }

    // MARK: - Path B (persistent variant): import a software CryptoKit key into the Keychain

    private static func importSoftwarePrivateKey(
        _ privateKey: P256.Signing.PrivateKey,
        label: String,
        accessibility: CFString
    ) throws -> SecKey {
        let secKey = try makeTransientSecKey(privateKey)

        var accessControlError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(nil, accessibility, [], &accessControlError) else {
            throw IdentityFactoryError.accessControlCreationFailed(
                description: accessControlError.map { String(describing: $0.takeRetainedValue()) } ?? "unknown"
            )
        }

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecValueRef: secKey,
            kSecAttrLabel: label,
            kSecAttrApplicationTag: Data(label.utf8),
            kSecAttrAccessControl: accessControl,
            kSecUseDataProtectionKeychain: false,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw IdentityFactoryError.keyPersistenceFailed(status: addStatus)
        }

        return secKey
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
