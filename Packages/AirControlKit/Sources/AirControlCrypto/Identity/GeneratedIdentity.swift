import Security
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The result of `IdentityFactory.makeIdentity`/`makeEphemeralIdentity`: a usable `SecIdentity` plus
/// the metadata callers need without re-deriving it (DER bytes for the trusted-device record, spec
/// §3.2.4; fingerprint for pinning, spec §3.2.1; which key backing was actually used, spec §7.1).
///
/// `SecIdentity` is a Core Foundation type. It is not automatically `Sendable`, but Security.framework's
/// CF types are safe to hand across isolation domains as opaque, effectively-immutable handles (Apple's
/// own Network.framework APIs that consume a `SecIdentity`/`sec_identity_t` are themselves used from
/// arbitrary queues), so this wrapper is `@unchecked Sendable`.
public struct GeneratedIdentity: @unchecked Sendable {
    public let secIdentity: SecIdentity
    public let certificateDER: Data
    public let fingerprint: Fingerprint
    public let backing: IdentityBackingKind
    /// The Keychain label this identity's key and certificate were stored under (empty for a factory
    /// path that did not persist, if one is ever added).
    public let label: String
    /// Which Keychain (or lack of one) actually persisted this identity — see `IdentityStoreTier`.
    /// Defaults to `.dataProtection` so existing call sites (this module's own `makeEphemeralIdentity`
    /// override below, and app-side call sites outside this package's edit scope) don't have to name
    /// it; those that care pass it explicitly.
    public let tier: IdentityStoreTier

    public init(
        secIdentity: SecIdentity,
        certificateDER: Data,
        fingerprint: Fingerprint,
        backing: IdentityBackingKind,
        label: String,
        tier: IdentityStoreTier = .dataProtection
    ) {
        self.secIdentity = secIdentity
        self.certificateDER = certificateDER
        self.fingerprint = fingerprint
        self.backing = backing
        self.label = label
        self.tier = tier
    }

    /// Builds the ARC-managed `sec_identity_t` Network.framework's
    /// `sec_protocol_options_set_local_identity` expects (spec §7.1/§7.2 code sample:
    /// `sec_protocol_options_set_local_identity(o, sec_identity_create(hostIdentity)!)`).
    ///
    /// `sec_identity_create` is declared in `Security/SecProtocolTypes.h`, so this fallback is available
    /// without importing `Network` (arch §3.1 rule 2/6: only apps and `aircontrol-cli` import `Network`).
    public var secIdentityT: sec_identity_t? {
        sec_identity_create(secIdentity)
    }
}
