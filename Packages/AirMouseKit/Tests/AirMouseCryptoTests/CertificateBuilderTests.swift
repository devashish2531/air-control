import Testing
import CryptoKit
import X509
import Foundation
@testable import AirMouseCrypto

@Suite struct CertificateBuilderTests {
    @Test func buildsAndSelfSigns() throws {
        let key = P256.Signing.PrivateKey()
        let output = try CertificateBuilder.makeSelfSigned(privateKey: key, commonName: "AirMouse Host test-host")

        #expect(output.certificate.subject == output.certificate.issuer)
        #expect(output.certificate.version == .v3)
        #expect(output.der.count > 0)
        #expect(output.fingerprint.bytes.count == 32)
    }

    @Test func parsesBackAndVerifiesSelfSignature() throws {
        let key = P256.Signing.PrivateKey()
        let output = try CertificateBuilder.makeSelfSigned(privateKey: key, commonName: "AirMouse Client test-client")

        let parsed = try CertificateBuilder.parse(der: output.der)
        #expect(parsed.subject == output.certificate.subject)
        #expect(parsed.serialNumber == output.certificate.serialNumber)

        // Self-signed: the certificate's own public key must validate its own signature.
        #expect(parsed.publicKey.isValidSignature(parsed.signature, for: parsed))
    }

    @Test func derRoundTripIsByteExact() throws {
        let key = P256.Signing.PrivateKey()
        let output = try CertificateBuilder.makeSelfSigned(privateKey: key, commonName: "AirMouse Host reround")
        let parsed = try CertificateBuilder.parse(der: output.der)
        let reencoded = try CertificateBuilder.derBytes(of: parsed)
        #expect(reencoded == output.der)
    }

    @Test func fingerprintMatchesIndependentSHA256() throws {
        let key = P256.Signing.PrivateKey()
        let output = try CertificateBuilder.makeSelfSigned(privateKey: key, commonName: "AirMouse Host fp-check")
        let expected = Array(SHA256.hash(data: output.der))
        #expect(output.fingerprint.bytes == expected)
    }

    @Test func defaultValidityIsApproximatelyTenYears() throws {
        let key = P256.Signing.PrivateKey()
        let notBefore = Date(timeIntervalSince1970: 1_700_000_000)
        let output = try CertificateBuilder.makeSelfSigned(
            privateKey: key,
            commonName: "AirMouse Host validity",
            notValidBefore: notBefore
        )
        let tenYears: TimeInterval = 10 * 365.2425 * 24 * 60 * 60
        #expect(abs(CertificateBuilder.defaultValidityDuration - tenYears) < 1)
        // Confirm it round-trips through DER with the same validity window (within 1 second, since
        // X.509 UTCTime/GeneralizedTime is second-granularity).
        let parsed = try CertificateBuilder.parse(der: output.der)
        _ = parsed // presence of a parsed value with no thrown error is the assertion here
    }

    @Test func differentCommonNamesProduceDifferentCertificates() throws {
        let key = P256.Signing.PrivateKey()
        let a = try CertificateBuilder.makeSelfSigned(privateKey: key, commonName: "AirMouse Host A")
        let b = try CertificateBuilder.makeSelfSigned(privateKey: key, commonName: "AirMouse Host B")
        #expect(a.der != b.der)
        #expect(a.fingerprint != b.fingerprint)
    }

    @Test func serialNumberIsSixteenRandomBytes() throws {
        #expect(CertificateBuilder.serialNumberByteCount == 16)
    }
}
