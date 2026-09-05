import Testing
import Security
import Foundation
@testable import AirMouseCrypto

/// `makeEphemeralIdentity` never touches the Keychain (see `IdentityFactory`'s type header), so these
/// tests should be reliable in any test environment, including sandboxed CI.
@Suite struct IdentityFactoryEphemeralTests {
    @Test func buildsAUsableSecIdentity() throws {
        let identity = try IdentityFactory.makeEphemeralIdentity(commonName: "AirMouse Host ephemeral-1")
        #expect(identity.backing == .software)
        #expect(identity.certificateDER.count > 0)
        #expect(identity.fingerprint.bytes.count == 32)

        var certificateRef: SecCertificate?
        let status = SecIdentityCopyCertificate(identity.secIdentity, &certificateRef)
        #expect(status == errSecSuccess)
        #expect(certificateRef != nil)
        if let certificateRef {
            let der = SecCertificateCopyData(certificateRef) as Data
            #expect(Array(der) == Array(identity.certificateDER))
        }
    }

    @Test func secIdentityTFallbackIsNonNil() throws {
        // spec §7.1/§7.2: `sec_protocol_options_set_local_identity` needs a `sec_identity_t`, built
        // here without importing Network.framework (see `GeneratedIdentity.secIdentityT`).
        let identity = try IdentityFactory.makeEphemeralIdentity(commonName: "AirMouse Host ephemeral-2")
        #expect(identity.secIdentityT != nil)
    }

    @Test func twoEphemeralIdentitiesHaveDifferentFingerprints() throws {
        let a = try IdentityFactory.makeEphemeralIdentity(commonName: "AirMouse Host ephemeral-A")
        let b = try IdentityFactory.makeEphemeralIdentity(commonName: "AirMouse Host ephemeral-B")
        #expect(a.fingerprint != b.fingerprint)
    }
}

/// `makeIdentity` touches the real Keychain (`SecItemAdd`, plus — on iOS only — optionally the Secure
/// Enclave). This is exactly the arch §7.1 spike R-1 risk area and is known to be unavailable in some
/// sandboxed test environments (no keychain access group entitlement, no unlocked login keychain,
/// etc.); per this module's task brief ("mark keychain-dependent tests to skip gracefully if the
/// keychain is unavailable"), these tests catch any `IdentityFactoryError` and treat it as an
/// environment-not-supported skip rather than a failure, after best-effort cleanup.
///
/// This lives inside `IdentityTierTests.swift`'s `IdentityTierRoundTripTests` suite (not its own
/// `@Suite` here) so it shares that suite's `.serialized` trait: every one of these tests mutates the
/// same real login Keychain, and Swift Testing's default parallel execution let this test race
/// `IdentityTierRoundTripTests`'s tests — observed empirically as a spurious `canSign` timeout and a
/// "deleteIdentity did not actually remove our own identity" failure, on *both* sides of the race —
/// when the two suites ran in different (parallel) suites.
extension IdentityTierRoundTripTests {
    @Test func persistedIdentityRoundTrip() throws {
        let label = "AirMouseCryptoTests.identity.\(UUID().uuidString)"
        defer { try? IdentityFactory.deleteIdentity(label: label) }

        do {
            let identity = try IdentityFactory.makeIdentity(
                // Unique per run, not a fixed string: Keychain Services overrides a *certificate*
                // item's stored `kSecAttrLabel` to the certificate's own subject common name (see
                // `IdentityTierTests.swift`'s identical fix/comment), so `deleteIdentity(label:)`'s
                // certificate-class query — which searches by `label` — only matches the certificate
                // this run created if the common name contains that same `label`. A fixed common name
                // here previously leaked one orphaned certificate item per test run.
                commonName: "AirMouse Host keychain-test \(label)",
                label: label,
                preferSecureEnclave: false
            )
            #expect(identity.certificateDER.count > 0)
            #expect(identity.backing == .keychainSecKey || identity.backing == .software)

            let store = KeychainIdentityStore()
            let loaded = try store.loadIdentity(label: label)
            #expect(loaded != nil)
        } catch is IdentityFactoryError {
            // Keychain unavailable in this environment (e.g. sandboxed CI) — nothing more to assert.
            return
        }
    }
}
