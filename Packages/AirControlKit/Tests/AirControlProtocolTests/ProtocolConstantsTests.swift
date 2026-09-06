import Foundation
import Testing
@testable import AirControlProtocol

/// Sanity checks pinning `ProtocolConstants` to the literal values in spec §3.0 / §11.3, so a
/// future edit that silently changes a wire constant is caught here rather than downstream.
@Suite struct ProtocolConstantsTests {
    @Test func networkAndVersion() {
        #expect(ProtocolConstants.protocolVersion == 1)
        #expect(ProtocolConstants.defaultTCPPort == 47_800)
        #expect(ProtocolConstants.defaultUDPPort == 47_800)
        #expect(ProtocolConstants.validPortRange == 1024...65535)
    }

    @Test func framingLimits() {
        #expect(ProtocolConstants.maxControlFrameBodyBytes == 262_144)
        #expect(ProtocolConstants.maxFrameLengthFieldValue == 262_145)
        #expect(ProtocolConstants.udpDatagramSize == 44)
    }

    @Test func sessionLimits() {
        #expect(ProtocolConstants.maxAuthenticatedSessions == 4)
        #expect(ProtocolConstants.maxPendingSessions == 2)
        #expect(ProtocolConstants.maxTrustedDevicesPerHost == 20)
        #expect(ProtocolConstants.maxTrustedHostsPerClient == 10)
    }

    @Test func rateLimits() {
        #expect(ProtocolConstants.controlMessageRatePerSecond == 200)
        #expect(ProtocolConstants.controlMessageBurst == 400)
        #expect(ProtocolConstants.pairingRateLimitPerMinutePerIP == 5)
    }

    @Test func qrAndPairing() {
        #expect(ProtocolConstants.qrURLMaxBytes == 512)
        #expect(ProtocolConstants.qrMaxAddresses == 6)
        #expect(ProtocolConstants.pairingSecretByteCount == 16)
        #expect(ProtocolConstants.pairingSecretLifetimeSeconds == 60)
        #expect(ProtocolConstants.pairingSecretMaxFailedAttempts == 3)
    }

    @Test func heartbeatAndTimeouts() {
        #expect(ProtocolConstants.heartbeatIntervalMs == 500)
        #expect(ProtocolConstants.sessionStaleTimeoutMs == 2_000)
        #expect(ProtocolConstants.sessionCloseTimeoutMs == 6_000)
    }

    @Test func replayAndMotionTiming() {
        #expect(ProtocolConstants.replayWindowSize == 64)
        #expect(ProtocolConstants.motionStaleApplyWindow == 8)
        #expect(ProtocolConstants.motionPauseGapMs == 100)
        #expect(ProtocolConstants.implicitScrollEndMs == 120)
        #expect(ProtocolConstants.motionInFlightDatagramCap == 2)
    }

    @Test func probeAndFallback() {
        #expect(ProtocolConstants.probeIntervalMs == 250)
        #expect(ProtocolConstants.probeWindowSize == 12)
        #expect(ProtocolConstants.probeFallbackLostThreshold == 11)
        #expect(ProtocolConstants.probeFallbackInitialUnansweredBurst == 8)
        #expect(ProtocolConstants.probeRecoveryAnsweredThreshold == 5)
        #expect(ProtocolConstants.tcpFallbackMaxFramesPerSecond == 60)
        #expect(ProtocolConstants.motionBatchMaxPayloadsPerFrame == 16)
    }

    @Test func macroLimits() {
        #expect(ProtocolConstants.macroMaxTotal == 64)
        #expect(ProtocolConstants.macroMaxPages == 6)
        #expect(ProtocolConstants.macroMaxPerPage == 12)
        #expect(ProtocolConstants.macroNameMaxLength == 24)
        #expect(ProtocolConstants.macroSequenceMaxSteps == 16)
        #expect(ProtocolConstants.macroScriptMaxBytes == 8_192)
        #expect(ProtocolConstants.macroShellCommandMaxBytes == 2_048)
        #expect(ProtocolConstants.macroURLMaxBytes == 2_048)
    }

    @Test func macroTimeouts() {
        #expect(ProtocolConstants.macroSequenceTimeoutSeconds == 30)
        #expect(ProtocolConstants.macroLaunchAppTimeoutSeconds == 10)
        #expect(ProtocolConstants.macroOpenURLTimeoutSeconds == 5)
        #expect(ProtocolConstants.macroShortcutTimeoutSeconds == 60)
        #expect(ProtocolConstants.macroScriptTimeoutSeconds == 30)
    }

    @Test func udpKeyRotation() {
        #expect(ProtocolConstants.udpKeyRotationCounterThreshold == 1 << 31)
        #expect(ProtocolConstants.udpKeyRotationIntervalSeconds == 4 * 3600)
        #expect(ProtocolConstants.udpKeyOverlapSeconds == 2)
        #expect(ProtocolConstants.udpCounterHardLimit == 1 << 32)
    }

    @Test func textAndMisc() {
        #expect(ProtocolConstants.textMessageMaxBytes == 16_384)
        #expect(ProtocolConstants.textRateCharsPerSecDefault == 500)
        #expect(ProtocolConstants.doubleClickIntervalMsDefault == 300)
        #expect(ProtocolConstants.sessionKeyValidForMsDefault == 14_400_000)
    }
}
