/// Typed failures from `IdentityFactory`. Every case carries the `OSStatus`/description Security.framework
/// gave us, since these failures are exactly the arch §7.1 R-1 risk area ("the most fiddly
/// security-critical piece") and need to be diagnosable without re-running under a debugger.
public enum IdentityFactoryError: Error, Sendable, Equatable {
    /// `SecAccessControlCreateWithFlags` failed.
    case accessControlCreationFailed(description: String)
    /// `SecKeyCreateRandomKey` failed (Path A: Keychain/Secure-Enclave key generation).
    case keyGenerationFailed(description: String)
    /// `SecKeyCreateWithData` failed while importing a software key (Path B).
    case keyImportFailed(description: String)
    /// `SecKeyCopyPublicKey`/`SecKeyCopyExternalRepresentation` failed while exporting the public key.
    case publicKeyExportFailed(description: String)
    /// The exported public key's X9.63 representation could not be parsed as a P-256 point.
    case publicKeyParseFailed
    /// `SecItemAdd(kSecClassKey, ...)` failed while persisting the private key.
    case keyPersistenceFailed(status: Int32)
    /// `SecCertificateCreateWithData` returned `nil`.
    case certificateImportFailed
    /// `SecItemAdd(kSecClassCertificate, ...)` failed while persisting the certificate.
    case certificatePersistenceFailed(status: Int32)
    /// `SecIdentityCreateWithCertificate` failed to find a matching private key for the certificate —
    /// the classic arch §7.1 R-1 failure mode.
    case identityLookupFailed(status: Int32)
    /// `SecItemDelete` failed while cleaning up a label.
    case deletionFailed(status: Int32)
}
