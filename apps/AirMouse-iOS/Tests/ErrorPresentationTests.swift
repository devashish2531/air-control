// Tests/ErrorPresentationTests.swift
// Checks `AppError` maps to the exact copy table of spec §9 (id, title, actions). Message bodies
// are exercised for the non-interpolated cases; interpolated cases are checked via `contains`
// for the fixed portion since the argument is caller-supplied.

import Testing
@testable import Air_Mouse

@Suite struct ErrorPresentationTests {
    @Test func localNetworkDenied() {
        let p = AppError.localNetworkDenied.presentation
        #expect(p.id == "E-LOCALNET")
        #expect(p.style == .alert)
        #expect(p.title == "Local network access is off")
        #expect(p.actions == [.openSettings])
    }

    @Test func cameraDenied() {
        let p = AppError.cameraDenied.presentation
        #expect(p.id == "E-CAMERA")
        #expect(p.actions == [.openSettings, .pasteLink])
    }

    @Test func noHostsFound() {
        let p = AppError.noHostsFound.presentation
        #expect(p.id == "E-NOHOSTS")
        #expect(p.actions == [.scanQR, .checkPermission])
    }

    @Test func isolatedNetwork() {
        let p = AppError.isolatedNetwork.presentation
        #expect(p.id == "E-ISOLATED")
        #expect(p.actions == [.retry, .howToUseHotspot])
    }

    @Test func connectionFailedInterpolatesHostName() {
        let p = AppError.connectionFailed(hostName: "Marcus's Mac").presentation
        #expect(p.id == "E-CONN-FAILED")
        #expect(p.title.contains("Marcus's Mac"))
        #expect(p.actions == [.retry, .scanQR])
    }

    @Test func pairingErrorsMapToDistinctIDs() {
        #expect(AppError.pairingURLInvalid.presentation.id == "E-PAIR-URL")
        #expect(AppError.pairingVersionMismatch.presentation.id == "E-PAIR-VERSION")
        #expect(AppError.pairingFingerprintMismatch.presentation.id == "E-PAIR-FP")
        #expect(AppError.pairingExpired.presentation.id == "E-PAIR-EXPIRED")
        #expect(AppError.pairingRateLimited.presentation.id == "E-PAIR-RATELIMIT")
        #expect(AppError.pairingDeviceLimit.presentation.id == "E-PAIR-FULL")
        #expect(AppError.pairingHostProofInvalid.presentation.id == "E-PAIR-HOSTPROOF")
    }

    // MARK: - Diagnostics-and-UX deliverable: new distinct cases (a)/(b)/(d)

    @Test func hostUnreachableOffersSettingsDeepLinkAndInterpolatesHostName() {
        let p = AppError.hostUnreachable(hostName: "Marcus's Mac").presentation
        #expect(p.id == "E-CONN-UNREACHABLE")
        #expect(p.style == .alert)
        #expect(p.title.contains("Marcus's Mac"))
        #expect(p.message.contains("same Wi-Fi"))
        #expect(p.message.contains("Local Network"))
        #expect(p.actions == [.openSettings, .retry])
    }

    @Test func tlsVerificationFailedIsDistinctFromPairingFingerprintMismatch() {
        let p = AppError.tlsVerificationFailed(hostName: "Marcus's Mac").presentation
        #expect(p.id == "E-TLS-MISMATCH")
        #expect(p.id != AppError.pairingFingerprintMismatch.presentation.id)
        #expect(p.title.contains("Marcus's Mac"))
        #expect(p.actions == [.forgetMac, .scanQR])
    }

    @Test func pairingWrongCodeIsDistinctFromPairingExpired() {
        let p = AppError.pairingWrongCode.presentation
        #expect(p.id == "E-PAIR-WRONGCODE")
        #expect(p.id != AppError.pairingExpired.presentation.id)
        #expect(p.actions == [.scanQR])
    }

    @Test func authErrors() {
        let untrusted = AppError.authUntrusted.presentation
        #expect(untrusted.id == "E-AUTH-UNTRUSTED")
        #expect(untrusted.actions == [.scanQR])

        let revoked = AppError.authRevoked.presentation
        #expect(revoked.id == "E-AUTH-REVOKED")
        #expect(revoked.actions == [.scanQR, .forgetMac])
    }

    @Test func versionMismatchErrors() {
        #expect(AppError.versionAppOutdated.presentation.id == "E-VERSION-APP")
        #expect(AppError.versionAppOutdated.presentation.actions == [.openAppStore])
        #expect(AppError.versionHelperOutdated.presentation.id == "E-VERSION-HELPER")
        #expect(AppError.versionHelperOutdated.presentation.actions == [.ok])
    }

    @Test func reconnectingBannerHasCancelAction() {
        let p = AppError.reconnecting(hostName: "Living Room Mac").presentation
        #expect(p.id == "E-RECONNECTING")
        #expect(p.style == .banner)
        #expect(p.title.contains("Living Room Mac"))
        #expect(p.actions == [.cancel])
    }

    @Test func udpFallbackIsBadgeWithNoActions() {
        let p = AppError.udpFallback.presentation
        #expect(p.id == "E-UDP-FALLBACK")
        #expect(p.style == .badge)
        #expect(p.title == "Elevated latency")
        #expect(p.actions.isEmpty)
    }

    @Test func macroToastsHaveNoActions() {
        #expect(AppError.macroBlocked.presentation.style == .toast)
        #expect(AppError.macroBlocked.presentation.actions.isEmpty)

        let failed = AppError.macroFailed(name: "Do Not Disturb", message: "timed out talking to System Settings").presentation
        #expect(failed.id == "E-MACRO-FAILED")
        #expect(failed.title.contains("Do Not Disturb"))
        #expect(failed.title.contains("timed out talking to System Settings"))

        let timeout = AppError.macroTimeout(name: "Do Not Disturb").presentation
        #expect(timeout.id == "E-MACRO-TIMEOUT")
        #expect(timeout.title.contains("Do Not Disturb"))

        #expect(AppError.macroNotFound.presentation.id == "E-MACRO-NOTFOUND")
    }

    @Test func textTooLongOffersTrim() {
        let p = AppError.textTooLong.presentation
        #expect(p.id == "E-TEXT-TOOLONG")
        #expect(p.title == "Text too long")
        #expect(p.actions == [.trim])
    }

    @Test func rateLimitedOffersReconnect() {
        let p = AppError.rateLimited.presentation
        #expect(p.id == "E-RATE")
        #expect(p.title == "Disconnected")
        #expect(p.actions == [.reconnect])
    }

    @Test func gyroInlineCasesHaveNoActions() {
        let none = AppError.gyroUnavailable.presentation
        #expect(none.id == "E-GYRO-NONE")
        #expect(none.style == .inline)
        #expect(none.actions.isEmpty)

        let calibrating = AppError.gyroCalibrating.presentation
        #expect(calibrating.id == "E-GYRO-CAL")
        #expect(calibrating.style == .inline)
    }

    @Test func genericFallbackCarriesCodeAsMessage() {
        let p = AppError.generic(code: "unexpectedThing").presentation
        #expect(p.id == "E-GENERIC")
        #expect(p.title == "Connection problem")
        #expect(p.message == "unexpectedThing")
        #expect(p.actions == [.reconnect])
    }

    @Test func everyRecoveryActionHasANonEmptyTitle() {
        for action in RecoveryAction.allCases {
            #expect(!action.title.isEmpty)
        }
    }
}
