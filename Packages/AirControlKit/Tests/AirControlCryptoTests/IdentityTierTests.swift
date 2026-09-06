import Testing
import Security
import Foundation
@testable import AirControlCrypto

/// REQUIRED FIX 2/5 (Keychain-identity-prompt defect): a `swift test` binary is unsigned, so
/// `IdentityStoreTier.dataProtection` always fails here (`errSecMissingEntitlement`) and every
/// identity created in this process lands on `.legacyNoPrompt` — exactly the "unsigned/ad-hoc/CI/test
/// build" scenario that tier exists for. These tests are therefore the automated, no-human-in-the-loop
/// proof that the tier's `SecACLSetContents(acl, nil, ...)` construction really does let *this same
/// process* sign immediately, with no `SecurityAgent` prompt to answer: `canSign` never blocks past its
/// timeout, so a test run that would otherwise hang forever waiting on an unanswerable prompt instead
/// fails fast and visibly.
///
/// `.serialized`: every test here mutates the real login Keychain under `kSecClassIdentity`/
/// `kSecClassKey`, and — a real, pre-existing platform quirk noted throughout this file —
/// `kSecClassIdentity` queries are not reliably filtered by label. Running these concurrently (Swift
/// Testing's default) let one test's `deleteIdentity`/`loadIdentity` race another's concurrently-alive
/// identity, observed empirically as a spurious "deleteIdentity did not actually remove our own
/// identity" failure; serializing this suite's tests relative to each other removes that self-race
/// (tests in *other* suites/files that also touch the Keychain can still interleave, but that's the
/// same pre-existing quirk, not something this trait is meant to solve).
@Suite(.serialized) struct IdentityTierRoundTripTests {
    @Test func createLoadSignDeleteRoundTrip() throws {
        let label = "AirControlCryptoTests.tier.\(UUID().uuidString)"
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
                commonName: "AirControl Host tier-roundtrip \(label)",
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

    /// Regression test for the "no persistent Keychain tier is usable
    /// (keyPersistenceFailed(status: -25304))" defect: `.legacyNoPrompt` used to persist its private key
    /// by importing a software `SecKey` via `SecItemAdd(kSecValueRef:)`, which a direct repro (a bare
    /// `swiftc`-built binary, no Xcode project or code signing involved) showed always fails with
    /// `errSecInvalidItemRef`/-25304 when adding to the legacy/file-based keychain, regardless of ACL
    /// attributes — the legacy keychain simply does not accept a "foreign" `SecKey` add via
    /// `kSecValueRef`. The fix (`IdentityFactory.makeNativeLegacyPrivateKey`) generates the key natively
    /// with `SecKeyCreateRandomKey` instead, exactly like `.dataProtection`, just with a no-prompt
    /// `SecAccess` ACL. This test creates a `.legacyNoPrompt` identity under a dedicated TEST label,
    /// loads it back, and proves it can sign immediately (no ACL prompt, no -25304), then deletes it.
    @Test func legacyNoPromptIdentityPersistsLoadsAndSignsWithoutInvalidItemRef() throws {
        let label = "AirControlCryptoTests.legacyNoPrompt.regression-25304.\(UUID().uuidString)"
        defer { try? IdentityFactory.deleteIdentity(label: label) }

        let created: GeneratedIdentity
        do {
            // Same unsigned-test-host reasoning as the round trip above: this always lands on
            // `.legacyNoPrompt` here, which is exactly the tier this regression test targets. Any
            // `IdentityFactoryError` here — in particular `.keyPersistenceFailed(status: -25304)` —
            // is the regression this test exists to catch, so let it fail the test rather than
            // swallowing it as an environment-skip (unlike the general round trip above, a Keychain-
            // less CI runner would fail differently — at `.dataProtection` too — which is out of scope
            // for this specific -25304 regression).
            created = try IdentityFactory.makeIdentity(
                commonName: "AirControl Host legacyNoPrompt-regression \(label)",
                label: label,
                preferSecureEnclave: false
            )
        } catch let error as IdentityFactoryError {
            if case .keyPersistenceFailed(let status) = error, status == -25304 {
                Issue.record("regression: .legacyNoPrompt key persistence failed with errSecInvalidItemRef (-25304)")
            }
            throw error
        }
        #expect(created.tier == .legacyNoPrompt)
        #expect(created.backing == .keychainSecKey)

        let store = KeychainIdentityStore()
        let maybeLoaded = try store.loadIdentity(label: label)
        let loaded = try #require(maybeLoaded, "loadIdentity found nothing right after makeIdentity persisted it")
        #expect(store.canSign(loaded, timeout: 5.0), "freshly created .legacyNoPrompt identity must be able to sign immediately")
    }

    @Test func legacyNoPromptTierIsUsedByThisUnsignedTestHost() throws {
        // Documents *why* the round trip above never needs a prompt: an unsigned test binary can never
        // reach `.dataProtection` (no `com.apple.application-identifier`), so `makeIdentity` always
        // falls back to `.legacyNoPrompt` here — this is the exact tier REQUIRED FIX 2 added.
        let label = "AirControlCryptoTests.tier.\(UUID().uuidString)"
        defer { try? IdentityFactory.deleteIdentity(label: label) }
        do {
            let created = try IdentityFactory.makeIdentity(
                commonName: "AirControl Host tier-check \(label)",
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
