import Testing
import Security
import CryptoKit
import Foundation
@testable import AirMouseCrypto

/// Exercises `TLSPinning`'s DER/fingerprint extraction against a real `SecTrust` built from a
/// self-signed certificate `CertificateBuilder` produces — the same shape the host/client verify
/// blocks see (spec §3.2.1), minus the live TLS handshake (constructing one of those in a unit test
/// would require a real Network.framework connection).
@Suite struct TLSPinningTests {
    private func makeSecTrust(der: Data) throws -> SecTrust {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw TestSetupError.certificateCreationFailed
        }
        let policy = SecPolicyCreateBasicX509()
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(certificate, policy, &trust)
        guard status == errSecSuccess, let trust else {
            throw TestSetupError.trustCreationFailed(status: status)
        }
        return trust
    }

    private enum TestSetupError: Error {
        case certificateCreationFailed
        case trustCreationFailed(status: OSStatus)
    }

    @Test func extractsLeafDERFromSingleCertificateTrust() throws {
        let key = P256.Signing.PrivateKey()
        let output = try CertificateBuilder.makeSelfSigned(privateKey: key, commonName: "AirMouse Host trust-test")
        let trust = try makeSecTrust(der: output.der)

        let extractedDER = try TLSPinning.leafCertificateDER(from: trust)
        #expect(Array(extractedDER) == Array(output.der))
    }

    @Test func computesMatchingFingerprint() throws {
        let key = P256.Signing.PrivateKey()
        let output = try CertificateBuilder.makeSelfSigned(privateKey: key, commonName: "AirMouse Host fp-trust-test")
        let trust = try makeSecTrust(der: output.der)

        let fingerprint = try TLSPinning.fingerprint(from: trust)
        #expect(fingerprint == output.fingerprint)
    }
}
