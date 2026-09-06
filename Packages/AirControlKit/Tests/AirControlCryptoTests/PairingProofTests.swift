import Testing
import CryptoKit
@testable import AirControlCrypto

@Suite struct PairingProofTests {
    private func makeBinding(hostIDHex: String, vector: [String: Any]) throws -> PairingBinding {
        try PairingBinding(
            exporter: hexDecode(vector["exporter_hex"] as! String),
            nonce: hexDecode(vector["nonce_hex"] as! String),
            clientFingerprint: hexDecode(vector["clientFP_hex"] as! String),
            hostFingerprint: hexDecode(vector["hostFP_hex"] as! String),
            hostID: hexDecode(hostIDHex)
        )
    }

    @Test func knownAnswerVector() throws {
        let vector = try VectorFile.load("pairing_proof_vector")
        let secret = SymmetricKey(data: hexDecode(vector["S_hex"] as! String))
        let binding = try makeBinding(hostIDHex: vector["hostID_hex"] as! String, vector: vector)

        let expectedProof = hexDecode(vector["proof_hex"] as! String)
        let expectedHostProof = hexDecode(vector["hostProof_hex"] as! String)

        #expect(PairingProof.clientProof(secret: secret, binding: binding) == expectedProof)
        #expect(PairingProof.hostProof(secret: secret, binding: binding) == expectedHostProof)

        #expect(PairingProof.verifyClientProof(expectedProof, secret: secret, binding: binding))
        #expect(PairingProof.verifyHostProof(expectedHostProof, secret: secret, binding: binding))
    }

    @Test func negativeVectorHostIDChangeProducesDifferentProof() throws {
        let vector = try VectorFile.load("pairing_proof_vector")
        let secret = SymmetricKey(data: hexDecode(vector["S_hex"] as! String))
        let negative = vector["negative_vector"] as! [String: Any]

        let corruptBinding = try makeBinding(hostIDHex: negative["hostID_hex"] as! String, vector: vector)
        let expectedCorruptProof = hexDecode(negative["proof_hex"] as! String)

        #expect(PairingProof.clientProof(secret: secret, binding: corruptBinding) == expectedCorruptProof)

        let originalProof = hexDecode(vector["proof_hex"] as! String)
        #expect(expectedCorruptProof != originalProof)
        #expect(PairingProof.verifyClientProof(originalProof, secret: secret, binding: corruptBinding) == false)
    }

    @Test func clientAndHostProofsDifferForSameBinding() throws {
        let vector = try VectorFile.load("pairing_proof_vector")
        let secret = SymmetricKey(data: hexDecode(vector["S_hex"] as! String))
        let binding = try makeBinding(hostIDHex: vector["hostID_hex"] as! String, vector: vector)

        #expect(PairingProof.clientProof(secret: secret, binding: binding) != PairingProof.hostProof(secret: secret, binding: binding))
    }

    @Test func wrongSecretFailsVerification() throws {
        let vector = try VectorFile.load("pairing_proof_vector")
        let binding = try makeBinding(hostIDHex: vector["hostID_hex"] as! String, vector: vector)
        let proof = hexDecode(vector["proof_hex"] as! String)

        let wrongSecret = SymmetricKey(data: [UInt8](repeating: 0xFF, count: 16))
        #expect(PairingProof.verifyClientProof(proof, secret: wrongSecret, binding: binding) == false)
    }

    @Test func prefixBytesMatchSpec() {
        #expect(PairingProof.clientPrefix == 0x01)
        #expect(PairingProof.hostPrefix == 0x02)
    }

    @Test func bindingRejectsWrongFieldLengths() {
        #expect(throws: (any Error).self) {
            _ = try PairingBinding(
                exporter: [UInt8](repeating: 0, count: 31), // wrong: should be 32
                nonce: [UInt8](repeating: 0, count: 16),
                clientFingerprint: [UInt8](repeating: 0, count: 32),
                hostFingerprint: [UInt8](repeating: 0, count: 32),
                hostID: [UInt8](repeating: 0, count: 16)
            )
        }
    }

    @Test func bindingTotalLengthIs128() throws {
        let vector = try VectorFile.load("pairing_proof_vector")
        let binding = try makeBinding(hostIDHex: vector["hostID_hex"] as! String, vector: vector)
        #expect(binding.bytes.count == 128)
        #expect(PairingBinding.totalLength == 128)
    }
}
