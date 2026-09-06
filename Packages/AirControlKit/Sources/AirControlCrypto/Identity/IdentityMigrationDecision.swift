/// Pure decision logic for REQUIRED FIX #3's migration step (see `KeychainIdentityStore
/// .migrateLegacyIdentityIfPossible`), pulled out of the actual Keychain calls so it can be unit
/// tested without touching the Keychain at all — every input is a plain `Bool` an agent/test can
/// inject.
public enum IdentityMigrationDecision: Sendable, Equatable {
    /// Re-add the existing key + certificate to the Data Protection keychain, then delete the legacy
    /// items — same key/certificate, so the host fingerprint (and every paired phone's pinned copy of
    /// it) never changes.
    case migrate
    /// Migration would require exporting/using a key whose ACL doesn't currently trust this process's
    /// signature (a prompt would block), or there's simply nothing on the Data Protection keychain to
    /// migrate *to* — fall back to the pre-existing "mint a fresh identity" replace path. Paired
    /// devices must re-pair.
    case replace
    /// Nothing to do: either there's no legacy item at all (fresh install, or already migrated), or
    /// the Data Protection keychain isn't available in this process (unsigned/ad-hoc/CI/test build) so
    /// there is nowhere to migrate to.
    case none

    /// - Parameters:
    ///   - legacyItemExists: whether `label` currently resolves to an identity stored in the legacy
    ///     (non-Data-Protection) keychain tier (`KeychainIdentityStore.loadIdentityWithTier`).
    ///   - dataProtectionAvailable: whether this process can actually use the Data Protection
    ///     keychain at all (i.e. `IdentityStoreTier.dataProtection` didn't just fail with
    ///     `errSecMissingEntitlement` or similar when minting a *fresh* identity would be attempted).
    ///   - canSignLegacy: `KeychainIdentityStore.canSign(_:)` on the legacy identity — a non-blocking,
    ///     timeout-guarded proxy for "would exporting/using this key risk a Keychain ACL prompt".
    public static func decide(
        legacyItemExists: Bool,
        dataProtectionAvailable: Bool,
        canSignLegacy: Bool
    ) -> IdentityMigrationDecision {
        guard legacyItemExists, dataProtectionAvailable else { return .none }
        return canSignLegacy ? .migrate : .replace
    }
}
