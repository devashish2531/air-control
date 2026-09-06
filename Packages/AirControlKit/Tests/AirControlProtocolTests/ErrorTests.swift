import Foundation
import Testing
@testable import AirControlProtocol

@Suite struct ErrorTests {
    @Test func errorPayloadRoundTripsWithKnownCode() throws {
        let payload = ErrorPayload(code: .pairingExpired, message: "Secret expired", ref: 42, fatal: true)
        let data = try ProtocolJSON.makeEncoder().encode(payload)
        let decoded = try ProtocolJSON.makeDecoder().decode(ErrorPayload.self, from: data)
        #expect(decoded == payload)
        #expect(decoded.knownCode == .pairingExpired)
    }

    @Test func errorPayloadRoundTripsWithUnknownCodeWithoutFailingToDecode() throws {
        let json = #"{"code":"future.newThing","message":"hi","fatal":false}"#
        let decoded = try ProtocolJSON.makeDecoder().decode(ErrorPayload.self, from: Data(json.utf8))
        #expect(decoded.code == "future.newThing")
        #expect(decoded.knownCode == nil)
    }

    @Test func errorPayloadRefIsOptional() throws {
        let json = #"{"code":"internal","message":"oops","fatal":false}"#
        let decoded = try ProtocolJSON.makeDecoder().decode(ErrorPayload.self, from: Data(json.utf8))
        #expect(decoded.ref == nil)
    }

    @Test func protocolErrorHasNonEmptyDescriptions() {
        let errors: [ProtocolError] = [
            .frameTooLarge(length: 300_000),
            .badFrame(reason: "unknown kind"),
            .badMessage(reason: "missing field"),
            .versionMismatch(min: 1, max: 1),
            .motionBatchInvalid(reason: "bad length"),
            .motionPayloadInvalid(reason: "bad source"),
            .invalidTXTRecord(field: "v", reason: "missing"),
            .invalidPairingURL(field: "s", reason: "missing"),
            .pairingURLTooLarge(length: 600),
            .macroValidation(reason: "too many"),
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!(error.errorDescription!.isEmpty))
        }
    }

    @Test func protocolErrorMapsToWireErrorCodeWhereDefined() {
        #expect(ProtocolError.frameTooLarge(length: 1).code == .frameTooLarge)
        #expect(ProtocolError.badFrame(reason: "x").code == .badFrame)
        #expect(ProtocolError.badMessage(reason: "x").code == .badMessage)
        #expect(ProtocolError.versionMismatch(min: 1, max: 1).code == .versionMismatch)
        #expect(ProtocolError.macroValidation(reason: "x").code == nil)
    }

    @Test func errorCodeRawValuesMatchWireDottedNamespace() {
        #expect(ErrorCode.frameTooLarge.rawValue == "protocol.frameTooLarge")
        #expect(ErrorCode.badFrame.rawValue == "protocol.badFrame")
        #expect(ErrorCode.badMessage.rawValue == "protocol.badMessage")
        #expect(ErrorCode.versionMismatch.rawValue == "protocol.versionMismatch")
        #expect(ErrorCode.authUntrusted.rawValue == "auth.untrusted")
        #expect(ErrorCode.authRevoked.rawValue == "auth.revoked")
        #expect(ErrorCode.pairingExpired.rawValue == "pairing.expired")
        #expect(ErrorCode.pairingInvalidProof.rawValue == "pairing.invalidProof")
        #expect(ErrorCode.pairingTooManyDevices.rawValue == "pairing.tooManyDevices")
        #expect(ErrorCode.rateLimited.rawValue == "rate.limited")
        #expect(ErrorCode.internalError.rawValue == "internal")
    }

    @Test func macroValidationErrorHasNonEmptyDescriptions() {
        let errors: [MacroValidationError] = [
            .nameEmpty(macro: ""),
            .nameTooLong(macro: "x", length: 30),
            .duplicateName(name: "Spotlight"),
            .invalidPage(macro: "x", page: 9),
            .tooManyMacros(count: 65),
            .tooManyOnPage(page: 0, count: 13),
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
        }
    }
}
