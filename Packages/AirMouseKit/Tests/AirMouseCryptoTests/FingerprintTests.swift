import Testing
import CryptoKit
import Foundation
@testable import AirMouseCrypto

@Suite struct FingerprintTests {
    @Test func isSHA256OfDER() {
        let der: [UInt8] = Array("not really a certificate, just some bytes".utf8)
        let fp = Fingerprint(certificateDER: der)
        let expected = Array(SHA256.hash(data: der))
        #expect(fp.bytes == expected)
        #expect(fp.bytes.count == 32)
        #expect(Fingerprint.byteCount == 32)
    }

    @Test func dataAndArrayInitsAgree() {
        let der: [UInt8] = [1, 2, 3, 4, 5]
        #expect(Fingerprint(certificateDER: der).bytes == Fingerprint(certificateDER: Data(der)).bytes)
    }

    @Test func hexStringRoundTrips() {
        let fp = Fingerprint(certificateDER: [9, 9, 9])
        let hex = fp.hexString
        #expect(hex.count == 64)
        let parsed = Fingerprint(hexString: hex)
        #expect(parsed?.bytes == fp.bytes)
    }

    @Test func hexStringIsLowercase() {
        let fp = Fingerprint(certificateDER: [0xFF, 0xAB])
        #expect(fp.hexString == fp.hexString.lowercased())
    }

    @Test func rejectsWrongLengthHex() {
        #expect(Fingerprint(bytes: [UInt8](repeating: 0, count: 31)) == nil)
        #expect(Fingerprint(hexString: "abcd") == nil)
        #expect(Fingerprint(hexString: String(repeating: "a", count: 63)) == nil) // odd length
    }

    @Test func shortLogPrefixIsEightHexChars() {
        // spec §7.4: "FP prefixes (8 hex)".
        let fp = Fingerprint(certificateDER: [1, 2, 3])
        #expect(fp.shortLogPrefix.count == 8)
        #expect(fp.hexString.hasPrefix(fp.shortLogPrefix))
    }

    @Test func txtRecordHintIsFirstSixteenBytesB64u() {
        // spec §3.1.2: TXT `fp` = "First 16 bytes of the host certificate FP", b64u, 22 chars.
        let fp = Fingerprint(certificateDER: [4, 5, 6])
        let hint = fp.txtRecordHint
        #expect(hint.count == 22)
        #expect(Base64URL.decode(hint) == Array(fp.bytes.prefix(16)))
    }

    @Test func equalityIsByteWise() {
        let a = Fingerprint(certificateDER: [1, 2, 3])
        let b = Fingerprint(certificateDER: [1, 2, 3])
        let c = Fingerprint(certificateDER: [1, 2, 4])
        #expect(a == b)
        #expect(a != c)
    }

    @Test func usableAsSetElement() {
        let a = Fingerprint(certificateDER: [1])
        let b = Fingerprint(certificateDER: [1])
        let set: Set<Fingerprint> = [a, b]
        #expect(set.count == 1)
    }
}
