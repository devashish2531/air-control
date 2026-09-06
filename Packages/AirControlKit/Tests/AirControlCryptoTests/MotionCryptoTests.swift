import Testing
import CryptoKit
import Foundation
@testable import AirControlCrypto

@Suite struct MotionCryptoTests {
    // spec §6.4 motion payload vector: {flags:0x00, source:0, samples:1, ts:0x00012345,
    // dx:+80, dy:-8, sx:0, sy:0} -> hex 00 00 01 00 45 23 01 00 50 00 F8 FF 00 00 00 00
    static let payload: [UInt8] = [0x00, 0x00, 0x01, 0x00, 0x45, 0x23, 0x01, 0x00, 0x50, 0x00, 0xF8, 0xFF, 0x00, 0x00, 0x00, 0x00]

    @Test func layoutConstants() {
        #expect(MotionCrypto.payloadLength == 16)
        #expect(MotionCrypto.headerLength == 12)
        #expect(MotionCrypto.tagLength == 16)
        #expect(MotionCrypto.datagramLength == 44)
    }

    @Test func nonceLayoutIsFourZeroBytesPlusCounterLE() {
        let nonce = MotionCrypto.nonceBytes(counter: 7)
        #expect(nonce == [0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0])
        #expect(nonce.count == 12)
    }

    @Test func headerLayoutIsSessionIDThenCounterLE() {
        let header = MotionDatagramHeader(sessionID: 0x0A0B0C0D, counter: 7)
        #expect(header.bytes == [0x0D, 0x0C, 0x0B, 0x0A, 7, 0, 0, 0, 0, 0, 0, 0])
    }

    @Test func knownAnswerVectorFromSpecSection6_4() throws {
        let vector = try VectorFile.load("hkdf_aead_vector")
        let secret = SessionSecret(bytes: hexDecode(vector["secret_hex"] as! String))!
        let sessionID = UInt32(vector["session_id"] as! Int)
        let counter = UInt64(vector["counter"] as! Int)
        let keys = SessionKeys.derive(secret: secret, sessionID: sessionID)

        var output = [UInt8](repeating: 0, count: MotionCrypto.datagramLength)
        try MotionCrypto.seal(payload: Self.payload, sessionID: sessionID, counter: counter, key: keys.clientToHost, into: &output)

        let expectedDatagram = hexDecode(vector["datagram_hex"] as! String)
        #expect(output == expectedDatagram)

        let opened = try MotionCrypto.open(datagram: output, key: keys.clientToHost)
        #expect(opened == Self.payload)
    }

    @Test func sealOpenRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        var output = [UInt8](repeating: 0, count: MotionCrypto.datagramLength)
        try MotionCrypto.seal(payload: Self.payload, sessionID: 99, counter: 12345, key: key, into: &output)
        let opened = try MotionCrypto.open(datagram: output, key: key)
        #expect(opened == Self.payload)
    }

    @Test func dataConvenienceRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let datagram = try MotionCrypto.seal(payload: Data(Self.payload), sessionID: 1, counter: 0, key: key)
        #expect(datagram.count == MotionCrypto.datagramLength)
        let opened = try MotionCrypto.open(datagram: datagram, key: key)
        #expect(Array(opened) == Self.payload)
    }

    @Test func rejectsWrongPayloadLength() {
        let key = SymmetricKey(size: .bits256)
        var output = [UInt8](repeating: 0, count: MotionCrypto.datagramLength)
        #expect(throws: MotionCryptoError.invalidPayloadLength(expected: 16, actual: 15)) {
            try MotionCrypto.seal(payload: [UInt8](repeating: 0, count: 15), sessionID: 1, counter: 0, key: key, into: &output)
        }
    }

    @Test func rejectsWrongOutputBufferLength() {
        let key = SymmetricKey(size: .bits256)
        var output = [UInt8](repeating: 0, count: 43)
        #expect(throws: MotionCryptoError.invalidOutputBufferLength(expected: 44, actual: 43)) {
            try MotionCrypto.seal(payload: Self.payload, sessionID: 1, counter: 0, key: key, into: &output)
        }
    }

    @Test func rejectsWrongDatagramLengthOnOpen() {
        let key = SymmetricKey(size: .bits256)
        #expect(throws: MotionCryptoError.invalidDatagramLength(expected: 44, actual: 43)) {
            _ = try MotionCrypto.open(datagram: [UInt8](repeating: 0, count: 43), key: key)
        }
    }

    @Test func tamperedTagIsRejected() throws {
        let key = SymmetricKey(size: .bits256)
        var datagram = [UInt8](repeating: 0, count: MotionCrypto.datagramLength)
        try MotionCrypto.seal(payload: Self.payload, sessionID: 1, counter: 0, key: key, into: &datagram)
        datagram[datagram.count - 1] ^= 0xFF // flip a tag byte

        #expect(throws: MotionCryptoError.authenticationFailed) {
            _ = try MotionCrypto.open(datagram: datagram, key: key)
        }
    }

    @Test func tamperedCiphertextIsRejected() throws {
        let key = SymmetricKey(size: .bits256)
        var datagram = [UInt8](repeating: 0, count: MotionCrypto.datagramLength)
        try MotionCrypto.seal(payload: Self.payload, sessionID: 1, counter: 0, key: key, into: &datagram)
        datagram[MotionCrypto.headerLength] ^= 0xFF // flip a ciphertext byte

        #expect(throws: MotionCryptoError.authenticationFailed) {
            _ = try MotionCrypto.open(datagram: datagram, key: key)
        }
    }

    @Test func tamperedHeaderIsRejectedBecauseItIsAAD() throws {
        let key = SymmetricKey(size: .bits256)
        var datagram = [UInt8](repeating: 0, count: MotionCrypto.datagramLength)
        try MotionCrypto.seal(payload: Self.payload, sessionID: 1, counter: 0, key: key, into: &datagram)
        datagram[0] ^= 0xFF // flip a sessionID byte (part of the AAD header)

        #expect(throws: MotionCryptoError.authenticationFailed) {
            _ = try MotionCrypto.open(datagram: datagram, key: key)
        }
    }

    @Test func wrongKeyIsRejected() throws {
        let key = SymmetricKey(size: .bits256)
        let wrongKey = SymmetricKey(size: .bits256)
        var datagram = [UInt8](repeating: 0, count: MotionCrypto.datagramLength)
        try MotionCrypto.seal(payload: Self.payload, sessionID: 1, counter: 0, key: key, into: &datagram)

        #expect(throws: MotionCryptoError.authenticationFailed) {
            _ = try MotionCrypto.open(datagram: datagram, key: wrongKey)
        }
    }

    @Test func peekHeaderDoesNotAuthenticate() throws {
        let key = SymmetricKey(size: .bits256)
        var datagram = [UInt8](repeating: 0, count: MotionCrypto.datagramLength)
        try MotionCrypto.seal(payload: Self.payload, sessionID: 0xAABBCCDD, counter: 42, key: key, into: &datagram)
        datagram[datagram.count - 1] ^= 0xFF // tamper the tag; header should still parse

        let header = MotionCrypto.peekHeader(datagram: datagram)
        #expect(header?.sessionID == 0xAABBCCDD)
        #expect(header?.counter == 42)
    }

    @Test func peekHeaderRejectsWrongLength() {
        #expect(MotionCrypto.peekHeader(datagram: [UInt8](repeating: 0, count: 10)) == nil)
    }

    @Test func openAuthenticatedCombinesKeyLookupAndReplay() throws {
        let key = SymmetricKey(size: .bits256)
        var datagram1 = [UInt8](repeating: 0, count: MotionCrypto.datagramLength)
        try MotionCrypto.seal(payload: Self.payload, sessionID: 7, counter: 0, key: key, into: &datagram1)
        var datagram2 = [UInt8](repeating: 0, count: MotionCrypto.datagramLength)
        try MotionCrypto.seal(payload: Self.payload, sessionID: 7, counter: 1, key: key, into: &datagram2)

        var window = ReplayWindow()

        let firstOpen = MotionCrypto.openAuthenticated(datagram: datagram1, resolveKey: { $0 == 7 ? key : nil }, window: &window)
        guard case .success(let payload) = firstOpen else { Issue.record("expected success"); return }
        #expect(payload == Self.payload)

        let replay = MotionCrypto.openAuthenticated(datagram: datagram1, resolveKey: { $0 == 7 ? key : nil }, window: &window)
        #expect(replay == .failure(.replay))

        let second = MotionCrypto.openAuthenticated(datagram: datagram2, resolveKey: { $0 == 7 ? key : nil }, window: &window)
        #expect(second.isSuccess)
    }

    @Test func openAuthenticatedReportsUnknownSessionID() throws {
        let key = SymmetricKey(size: .bits256)
        var datagram = [UInt8](repeating: 0, count: MotionCrypto.datagramLength)
        try MotionCrypto.seal(payload: Self.payload, sessionID: 5, counter: 0, key: key, into: &datagram)
        var window = ReplayWindow()

        let result = MotionCrypto.openAuthenticated(datagram: datagram, resolveKey: { _ in nil }, window: &window)
        #expect(result == .failure(.unknownSessionID))
    }

    @Test func openAuthenticatedReportsWrongLength() {
        var window = ReplayWindow()
        let result = MotionCrypto.openAuthenticated(datagram: [0, 1, 2], resolveKey: { _ in nil }, window: &window)
        #expect(result == .failure(.wrongLength))
    }
}

private extension Result where Success == [UInt8], Failure == MotionCrypto.OpenFailure {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
