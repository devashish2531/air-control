/// Which Keychain (or lack of one) actually persisted a `GeneratedIdentity` — orthogonal to
/// `IdentityBackingKind` (which describes the private-key *generation* strategy: Secure Enclave vs.
/// plain Keychain `SecKey` vs. a software CryptoKit key). This axis instead answers "which ACL/prompt
/// model governs this key", which is exactly the defect this ladder (`IdentityFactory`,
/// `KeychainIdentityStore`) works around: a legacy-keychain item's default ACL trusts only the
/// *creating* process's code signature, so any rebuild with a different signature (ad-hoc vs.
/// team-signed, or any ad-hoc rebuild) routes `SecKeyCreateSignature` through a `SecurityAgent`
/// prompt that a menu-bar helper can never answer.
///
/// Graceful-degradation order (macOS): `.dataProtection` → `.legacyNoPrompt` → (caller's own
/// `.ephemeral` fallback via `IdentityFactory.makeEphemeralIdentity`, never persisted at all).
public enum IdentityStoreTier: String, Sendable, Equatable, CaseIterable {
    /// The Data Protection keychain (`kSecUseDataProtectionKeychain: true`). No per-application ACL —
    /// access is instead gated on the signed app's `com.apple.application-identifier` (and, for
    /// shared groups, `keychain-access-groups`), so it survives ad-hoc/team re-signs without ever
    /// prompting. Requires the running app to carry that entitlement (Xcode adds it automatically for
    /// team-signed builds); unsigned/ad-hoc/CI builds can't use this tier at all
    /// (`errSecMissingEntitlement`, -34018).
    case dataProtection
    /// The legacy (file-based) keychain, but with a `SecAccess`/`SecACL` explicitly opened to any
    /// application (`SecACLSetContents(acl, nil, ...)`) instead of the default "trust only the
    /// creating signature" ACL — so it never prompts either, at the cost of the Data Protection
    /// keychain's stronger access guarantees. macOS only (this whole legacy-keychain concept doesn't
    /// exist on iOS); the fallback for unsigned/ad-hoc/CI builds that can't reach `.dataProtection`.
    case legacyNoPrompt
    /// In-memory only (`IdentityFactory.makeEphemeralIdentity`) — never touches any keychain, so it
    /// can never fail or prompt, but doesn't survive a relaunch. The last-resort fallback when neither
    /// keychain tier is usable.
    case ephemeral
}
