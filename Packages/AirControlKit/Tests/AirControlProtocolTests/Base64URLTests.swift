import Foundation
import Testing
@testable import AirControlProtocol

@Suite struct Base64URLTests {
    @Test func encodesWithoutPaddingAndUrlSafeAlphabet() {
        // Standard base64 of 0xFB 0xFF 0xBF would be "+/+/" style bytes; pick bytes that produce
        // '+' and '/' in standard base64 to confirm they become '-' and '_'.
        let data = Data([0xFB, 0xFF, 0xBF])
        let standard = data.base64EncodedString()
        #expect(standard.contains("+") || standard.contains("/"))

        let encoded = data.b64u
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(!encoded.contains("="))
    }

    @Test func decodesBackToOriginalBytes() {
        for length in [0, 1, 2, 3, 4, 5, 16, 32] {
            let data = Data((0..<length).map { UInt8($0 % 256) })
            let decoded = Data(b64u: data.b64u)
            #expect(decoded == data)
        }
    }

    @Test func decodeRejectsInvalidCharacters() {
        #expect(Data(b64u: "not valid!!! b64u") == nil)
    }

    @Test func knownVector() {
        // "hello" -> base64 "aGVsbG8=" -> b64u "aGVsbG8"
        let data = Data("hello".utf8)
        #expect(data.b64u == "aGVsbG8")
        #expect(Data(b64u: "aGVsbG8") == data)
    }

    @Test func decodesPaddedInputToo() {
        // b64u is defined as *without* padding, but decoding should tolerate padded input.
        #expect(Data(b64u: "aGVsbG8=") == Data("hello".utf8))
    }
}
