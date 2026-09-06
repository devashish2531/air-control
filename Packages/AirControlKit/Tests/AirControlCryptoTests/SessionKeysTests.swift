import Testing
import CryptoKit
@testable import AirControlCrypto

@Suite struct SessionKeysTests {
    @Test func saltIsSessionIDLittleEndian() {
        let salt = SessionKeys.salt(sessionID: 0x0A0B0C0D)
        #expect(Array(salt) == [0x0D, 0x0C, 0x0B, 0x0A])
    }

    @Test func knownAnswerVectorFromSpecSection6_4() throws {
        let vector = try VectorFile.load("hkdf_aead_vector")
        let secret = SessionSecret(bytes: hexDecode(vector["secret_hex"] as! String))!
        let sessionID = UInt32(vector["session_id"] as! Int)

        let keys = SessionKeys.derive(secret: secret, sessionID: sessionID)

        let expectedC2H = hexDecode(vector["kC2H_hex"] as! String)
        let expectedH2C = hexDecode(vector["kH2C_hex"] as! String)

        keys.clientToHost.withUnsafeBytes { #expect(Array($0) == expectedC2H) }
        keys.hostToClient.withUnsafeBytes { #expect(Array($0) == expectedH2C) }
    }

    @Test func directionalKeysDiffer() throws {
        let secret = try SessionSecret.generate()
        let keys = SessionKeys.derive(secret: secret, sessionID: 42)
        keys.clientToHost.withUnsafeBytes { c2h in
            keys.hostToClient.withUnsafeBytes { h2c in
                #expect(Array(c2h) != Array(h2c))
            }
        }
    }

    @Test func differentSessionIDsDeriveDifferentKeys() throws {
        let secret = try SessionSecret.generate()
        let keysA = SessionKeys.derive(secret: secret, sessionID: 1)
        let keysB = SessionKeys.derive(secret: secret, sessionID: 2)
        keysA.clientToHost.withUnsafeBytes { a in
            keysB.clientToHost.withUnsafeBytes { b in
                #expect(Array(a) != Array(b))
            }
        }
    }

    @Test func rejectsWrongSecretLength() {
        #expect(SessionSecret(bytes: [UInt8](repeating: 0, count: 31)) == nil)
        #expect(SessionSecret(bytes: [UInt8](repeating: 0, count: 33)) == nil)
        #expect(SessionSecret(bytes: [UInt8](repeating: 0, count: 32)) != nil)
    }
}
