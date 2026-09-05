import Testing
import Security
import Foundation
@testable import AirMouseCrypto

/// REQUIRED FIX 2/5 (Keychain-identity-prompt defect): a `swift test` binary is unsigned, so
/// `IdentityStoreTier.dataProtection` always fails here (`errSecMissingEntitlement`) and every
/// identity created in this process lands on `.legacyNoPrompt` — exactly the "unsigned/ad-hoc/CI/test
/// build" scenario that tier exists for. These tests are therefore the automated, no-human-in-the-loop
/// proof that the tier's `SecACLSetContents(acl, nil, ...)` construction really does let *this same
/// process* sign immediately, with no `SecurityAgent` prompt to answer: `canSign` never blocks past its
/// timeout, so a test run that would otherwise hang forever waiting on an unanswerable prompt instead
/// fails fast and visibly.
@Suite struct IdentityTierRoundTripTests {
    @Test func createLoadSignDeleteRoundTrip() throws {
        let label = "AirMouseCryptoTests.tier.\(UUID().uuidString)"
        defer { try? IdentityFactory.deleteIdentity(label: label) }

        let created: GeneratedIdentity
        do {
            created = try IdentityFactory.makeIdentity(
                // Unique per run, not just `label`: a certificate's *stored* `kSecAttrLabel` is
                // overridden by Keychain Services to the certificate's own subject common name
                // (a real, pre-existing macOS quirk, independent of this fix) rather than the value
                // this call requests — so two runs sharing one common name would leave two
                // same-"labeled" certs behind, and `kSecClassIdentity` queries are not reliably
                // filtered by label to begin with. Keeping the common name unique per run is what
                // actually keeps this test (and its cleanup) deterministic.
                commonName: "AirMouse Host tier-roundtrip \(label)",
                label: label,
                preferSecureEnclave: false
            )
        } catch is IdentityFactoryError {
            // No Keychain access at all in this environment (e.g. a fully sandboxed CI runner with
            // neither tier available) — nothing more to assert, per this module's "skip gracefully"
            // brief (see `IdentityFactoryKeychainTests`).
            return
        }
        #expect(created.certificateDER.count > 0)

        // Unsigned test host: Data Protection keychain access needs `com.apple.application-identifier`,
        // which no `swift test` binary carries, so this always lands on `.legacyNoPrompt` here. If it
        // somehow lands on `.dataProtection` (e.g. a future signed-test-host setup), that's fine too —
        // the round trip below doesn't depend on which tier was used.
        let store = KeychainIdentityStore()
        guard let loaded = try store.loadIdentity(label: label) else {
            Issue.record("loadIdentity found nothing right after makeIdentity persisted it")
            return
        }

        // The whole point of both persistent tiers: signing must succeed *immediately*, never routing
        // through a `SecurityAgent` confirmation this headless test process could never answer.
        // `canSign` itself never blocks past its timeout either way, so this assertion is the
        // regression test for the original defect (a stalled/failed signature attempt here).
        #expect(store.canSign(loaded, timeout: 5.0))

        try IdentityFactory.deleteIdentity(label: label)
        // Not a plain `== nil`: `kSecClassIdentity` queries are not reliably filtered by label on this
        // platform (a real, pre-existing quirk — see the common-name comment above), so a *different*,
        // concurrently-alive test's identity can legitimately come back for this label. What actually
        // matters for "delete worked" is that *our own* identity is gone.
        if let stillFound = try store.loadIdentity(label: label) {
            var certificateRef: SecCertificate?
            SecIdentityCopyCertificate(stillFound, &certificateRef)
            let der = certificateRef.map { SecCertificateCopyData($0) as Data }
            #expect(der != created.certificateDER, "deleteIdentity did not actually remove our own identity")
        }
    }

    @Test func legacyNoPromptTierIsUsedByThisUnsignedTestHost() throws {
        // Documents *why* the round trip above never needs a prompt: an unsigned test binary can never
        // reach `.dataProtection` (no `com.apple.application-identifier`), so `makeIdentity` always
        // falls back to `.legacyNoPrompt` here — this is the exact tier REQUIRED FIX 2 added.
        let label = "AirMouseCryptoTests.tier.\(UUID().uuidString)"
        defer { try? IdentityFactory.deleteIdentity(label: label) }
        do {
            let created = try IdentityFactory.makeIdentity(
                commonName: "AirMouse Host tier-check \(label)",
                label: label,
                preferSecureEnclave: false
            )
            #expect(created.tier == .legacyNoPrompt)
        } catch is IdentityFactoryError {
            return
        }
    }
}

/// Pure, Keychain-free unit tests for the migration decision logic (REQUIRED FIX 3/5): every input is
/// an injectable `Bool`, so these run identically everywhere (no environment dependency at all).
@Suite struct IdentityMigrationDecisionTests {
    @Test func migratesWhenLegacyItemExistsAndDataProtectionIsAvailableAndSignable() {
        #expect(
            IdentityMigrationDecision.decide(legacyItemExists: true, dataProtectionAvailable: true, canSignLegacy: true)
                == .migrate
        )
    }

    @Test func replacesWhenLegacyItemExistsButCannotBeSignedWithoutRiskingAPrompt() {
        // ACL doesn't currently trust this process's signature — exporting the key to migrate it would
        // risk the exact prompt this whole fix exists to avoid, so fall back to the pre-existing
        // replace-on-unusable path instead.
        #expect(
            IdentityMigrationDecision.decide(legacyItemExists: true, dataProtectionAvailable: true, canSignLegacy: false)
                == .replace
        )
    }

    @Test func doesNothingWhenDataProtectionIsUnavailable() {
        // Nowhere to migrate *to* (unsigned/ad-hoc/CI/test build) — even a signable legacy item is left
        // alone rather than needlessly replaced.
        #expect(
            IdentityMigrationDecision.decide(legacyItemExists: true, dataProtectionAvailable: false, canSignLegacy: true)
                == .none
        )
        #expect(
            IdentityMigrationDecision.decide(legacyItemExists: true, dataProtectionAvailable: false, canSignLegacy: false)
                == .none
        )
    }

    @Test func doesNothingWhenThereIsNoLegacyItem() {
        // Fresh install (already on `.dataProtection`, or no identity yet) — nothing to migrate.
        #expect(
            IdentityMigrationDecision.decide(legacyItemExists: false, dataProtectionAvailable: true, canSignLegacy: true)
                == .none
        )
        #expect(
            IdentityMigrationDecision.decide(legacyItemExists: false, dataProtectionAvailable: false, canSignLegacy: false)
                == .none
        )
    }
}
