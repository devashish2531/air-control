import CryptoKit
import Security
import X509
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Mints self-signed P-256 X.509 certificates per spec §3.2.1:
///
/// | Aspect | Value |
/// |---|---|
/// | Certificate | Self-signed X.509 v3 built with `swift-certificates`, validity 10 years, serial random 16 bytes, EKU serverAuth+clientAuth, no SAN |
/// | CN | `AirControl Host <hostID b64u>` (host) / `AirControl Client <clientID b64u>` (client) |
///
/// This type only builds the certificate and its DER encoding; it never touches the Keychain (that is
/// `IdentityFactory`'s job) and accepts *any* signing key that swift-certificates can wrap as a
/// `Certificate.PrivateKey` (a software `P256.Signing.PrivateKey`, or — via the `signingKey:publicKey:`
/// overload — a Keychain-backed `SecKey`, spec §7.1 Path A/B), so it is fully testable without the
/// Keychain (Path B / software keys) while still serving Path A (Keychain `SecKey`, arch §7.1) through
/// the same code.
///
/// DER export goes through `SecCertificate.makeWithCertificate(_:)` / `SecCertificateCopyData`
/// (both declared by `X509`/`Security` when `Security` is importable) rather than calling
/// `SwiftASN1.DER.Serializer` directly, because this package's manifest exposes only the `X509` product
/// to this target (not `SwiftASN1` itself) — see the module header's import list.
public enum CertificateBuilder: Sendable {
    /// Default certificate validity: 10 years (spec §3.2.1, §7.3).
    // TODO(integration): move to ProtocolConstants.
    public static let defaultValidityDuration: TimeInterval = 10 * 365.2425 * 24 * 60 * 60

    /// Serial number length (spec §3.2.1: "serial random 16 bytes").
    public static let serialNumberByteCount = 16

    /// Default EKU set for both host and client leaf certs (spec §3.2.1: "EKU serverAuth+clientAuth",
    /// both directions, since either side may act as the TLS server or client — the host is always the
    /// listener but the spec calls for both usages on both certs).
    public static let defaultExtendedKeyUsages: [ExtendedKeyUsage.Usage] = [.serverAuth, .clientAuth]

    /// A minted certificate plus its DER encoding and fingerprint.
    public struct Output: Sendable {
        public let certificate: Certificate
        public let der: Data
        public let fingerprint: Fingerprint

        public init(certificate: Certificate, der: Data) {
            self.certificate = certificate
            self.der = der
            self.fingerprint = Fingerprint(certificateDER: der)
        }
    }

    /// Builds and self-signs a certificate whose subject and issuer are both `commonName`, and whose
    /// public key is `publicKey`; the signature is produced by `signingKey`, which may wrap the same
    /// key material as `publicKey` (software) or a Keychain/Secure-Enclave `SecKey` whose public half
    /// matches `publicKey` (Path A/B, spec §7.1).
    public static func makeSelfSigned(
        publicKey: P256.Signing.PublicKey,
        signingKey: Certificate.PrivateKey,
        commonName: String,
        notValidBefore: Date = Date(),
        validityDuration: TimeInterval = defaultValidityDuration,
        extendedKeyUsages: [ExtendedKeyUsage.Usage] = defaultExtendedKeyUsages
    ) throws -> Output {
        let subjectName = try DistinguishedName {
            CommonName(commonName)
        }

        let serial = Certificate.SerialNumber(bytes: try SecureRandom.bytes(count: serialNumberByteCount))

        let extensions = try Certificate.Extensions {
            // No SAN (spec §3.2.1: "no SAN") and not a CA — this is always a self-signed leaf pinned
            // directly by fingerprint, never used to issue other certificates.
            Critical(BasicConstraints.notCertificateAuthority)
            Critical(KeyUsage(digitalSignature: true))
            try ExtendedKeyUsage(extendedKeyUsages)
        }

        let certificate = try Certificate(
            version: .v3,
            serialNumber: serial,
            publicKey: Certificate.PublicKey(publicKey),
            notValidBefore: notValidBefore,
            notValidAfter: notValidBefore.addingTimeInterval(validityDuration),
            issuer: subjectName,
            subject: subjectName,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: signingKey
        )

        let der = try derBytes(of: certificate)
        return Output(certificate: certificate, der: der)
    }

    /// Convenience for the common software-key case (spec §7.1 Path B, and any test that does not need
    /// the Keychain): the same key both signs and is the subject's public key.
    public static func makeSelfSigned(
        privateKey: P256.Signing.PrivateKey,
        commonName: String,
        notValidBefore: Date = Date(),
        validityDuration: TimeInterval = defaultValidityDuration,
        extendedKeyUsages: [ExtendedKeyUsage.Usage] = defaultExtendedKeyUsages
    ) throws -> Output {
        try makeSelfSigned(
            publicKey: privateKey.publicKey,
            signingKey: Certificate.PrivateKey(privateKey),
            commonName: commonName,
            notValidBefore: notValidBefore,
            validityDuration: validityDuration,
            extendedKeyUsages: extendedKeyUsages
        )
    }

    /// DER-encodes `certificate` via `SecCertificate` round trip (see type header for why).
    public static func derBytes(of certificate: Certificate) throws -> Data {
        let secCertificate = try SecCertificate.makeWithCertificate(certificate)
        return SecCertificateCopyData(secCertificate) as Data
    }

    /// Parses DER bytes back into a `Certificate` (used by tests to round-trip what `makeSelfSigned`
    /// produced, and available to callers that need to re-parse a stored certificate).
    public static func parse(der: Data) throws -> Certificate {
        try Certificate(derEncoded: Array(der))
    }
}
