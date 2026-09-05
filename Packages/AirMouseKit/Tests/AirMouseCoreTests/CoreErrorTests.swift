import Testing
@testable import AirMouseCore
import AirMouseProtocol

@Suite struct CoreErrorTests {
    @Test func pairingExpiredMapsToPairingCategory() {
        let error = CoreError(wire: ErrorPayload(code: "pairing.expired", message: "expired", fatal: true))
        #expect(error == .pairingExpired)
        #expect(error.category == .pairing)
        #expect(error.wireCode == .pairingExpired)
    }

    @Test func authUntrustedMapsToAuthenticationCategory() {
        let error = CoreError(wire: ErrorPayload(code: "auth.untrusted", message: "nope", fatal: true))
        #expect(error == .authUntrusted)
        #expect(error.category == .authentication)
    }

    @Test func rateLimitedMapsToRateLimitedCategory() {
        let error = CoreError(wire: ErrorPayload(code: "rate.limited", message: "slow down", fatal: true))
        #expect(error == .rateLimited)
        #expect(error.category == .rateLimited)
    }

    @Test func macroBlockedMapsToMacroCategory() {
        let error = CoreError(wire: ErrorPayload(code: "macro.blockedByPolicy", message: "no", fatal: false))
        #expect(error == .macroBlockedByPolicy)
        #expect(error.category == .macro)
    }

    @Test func unrecognizedCodeMapsToInternalFailure() {
        let error = CoreError(wire: ErrorPayload(code: "some.futureCode", message: "huh", fatal: false))
        if case .internalFailure = error {
            // expected
        } else {
            Issue.record("expected .internalFailure, got \(error)")
        }
        #expect(error.category == .internalFailure)
    }

    @Test func versionMismatchCategoryIsProtocolMismatch() {
        let error = CoreError.versionMismatch(min: 1, max: 1, peerVersion: "2.0")
        #expect(error.category == .protocolMismatch)
        #expect(error.wireCode == .versionMismatch)
    }

    @Test func protocolViolationForwardsInnerWireCode() {
        let error = CoreError.protocolViolation(.badMessage(reason: "missing field"))
        #expect(error.wireCode == .badMessage)
        #expect(error.category == .protocolMismatch)
    }
}

