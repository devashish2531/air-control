/// Which key storage actually backed a `GeneratedIdentity` (spec §7.1 Path A/B, §7.1: "recorded in
/// `hostState`/diagnostics as `identity: software`" when Path B was used).
public enum IdentityBackingKind: String, Sendable, Equatable, CaseIterable {
    /// Path A, Secure Enclave: `kSecAttrTokenIDSecureEnclave` (iOS client only, spec §3.2.1).
    case secureEnclave
    /// Path A, plain Keychain-resident `SecKey` (host; or client when Secure Enclave is unavailable).
    case keychainSecKey
    /// Path B fallback: software `P256.Signing.PrivateKey` imported into the Keychain as a permanent
    /// `SecKey` so `SecIdentityCreateWithCertificate` can still find it (spec §7.1 Path B).
    case software
}
