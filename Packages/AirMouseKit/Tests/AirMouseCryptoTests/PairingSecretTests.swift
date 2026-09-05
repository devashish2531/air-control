import Testing
import Foundation
@testable import AirMouseCrypto

@Suite struct PairingSecretTests {
    @Test func generatedSecretIsSixteenBytes() throws {
        let secret = try PairingSecret.generate()
        #expect(secret.bytes.count == 16)
        #expect(PairingSecret.byteCount == 16)
    }

    @Test func validityWindowIsSixtySeconds() {
        let issued = Date(timeIntervalSince1970: 1_000_000)
        let secret = PairingSecret(bytes: [UInt8](repeating: 0xAB, count: 16), issuedAt: issued)!

        #expect(secret.isValid(at: issued) == true)
        #expect(secret.isValid(at: issued.addingTimeInterval(59)) == true)
        #expect(secret.isValid(at: issued.addingTimeInterval(60)) == false)
        #expect(secret.isValid(at: issued.addingTimeInterval(61)) == false)
        #expect(PairingSecret.validityDuration == 60)
    }

    @Test func maxAttemptsIsThree() {
        #expect(PairingSecret.maxAttempts == 3)
    }

    @Test func rejectsWrongByteLength() {
        #expect(PairingSecret(bytes: [UInt8](repeating: 0, count: 15), issuedAt: Date()) == nil)
        #expect(PairingSecret(bytes: [UInt8](repeating: 0, count: 17), issuedAt: Date()) == nil)
    }

    @Test func base64URLRoundTrip() {
        let original = PairingSecret(bytes: (0..<16).map { UInt8($0) }, issuedAt: Date(timeIntervalSince1970: 42))!
        let encoded = original.base64URLEncoded
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(!encoded.contains("="))

        let decoded = PairingSecret(base64URLEncoded: encoded, issuedAt: Date(timeIntervalSince1970: 42))
        #expect(decoded?.bytes == original.bytes)
    }

    @Test func rejectsMalformedBase64URL() {
        #expect(PairingSecret(base64URLEncoded: "not base64url!!", issuedAt: Date()) == nil)
    }

    @Test func hmacKeyUsableByPairingProof() throws {
        let secret = try PairingSecret.generate()
        let binding = try PairingBinding(
            exporter: [UInt8](repeating: 1, count: 32),
            nonce: [UInt8](repeating: 2, count: 16),
            clientFingerprint: [UInt8](repeating: 3, count: 32),
            hostFingerprint: [UInt8](repeating: 4, count: 32),
            hostID: [UInt8](repeating: 5, count: 16)
        )
        let proof = PairingProof.clientProof(secret: secret.hmacKey, binding: binding)
        #expect(proof.count == 32)
    }
}
