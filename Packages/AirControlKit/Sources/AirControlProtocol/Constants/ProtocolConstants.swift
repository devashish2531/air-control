import Foundation

/// Every normative constant from spec §3.0 ("Conventions and global limits") and §11.3
/// ("Constants table"), collected in one place so no other module or app hardcodes a wire
/// literal (CLAUDE.md: "every wire constant comes from `AirControlProtocol` constants, never
/// literals in apps"). Each constant's doc comment cites the spec row it reproduces.
///
/// This module imports only Foundation, so these are plain value constants — no platform
/// framework needed to read a timeout or a byte limit.
public enum ProtocolConstants {

    // MARK: - §3.0 Conventions and global limits

    /// Protocol major version this build of `AirControlProtocol` speaks. spec §3.0: "Protocol
    /// version | `1` (integer). Independent of app semantic versions (NFR-OSS-007)."
    public static let protocolVersion: Int = 1

    /// Max control frame **payload** (body after the 1-byte `kind`), in bytes. spec §3.0: "Max
    /// control frame | 262 144 bytes (256 KiB) payload; larger → `protocol.frameTooLarge`,
    /// connection closed." Also spec §3.4.1: framing `length` field is `1 ≤ length ≤ 262145`.
    public static let maxControlFrameBodyBytes: Int = 262_144

    /// Maximum legal value of the framing `length` field itself (`1` byte `kind` + body). spec
    /// §3.4.1: "1 ≤ length ≤ 262 145".
    public static let maxFrameLengthFieldValue: UInt32 = UInt32(maxControlFrameBodyBytes) + 1

    /// Exact UDP datagram size; anything else is dropped silently. spec §3.0 and §3.5.1: "Max UDP
    /// datagram | 44 bytes exactly (28-byte AEAD framing + 16-byte payload)".
    public static let udpDatagramSize: Int = 44

    /// spec §3.0: "Max simultaneous sessions | 4 authenticated + 2 pending ...; a 7th TCP
    /// connection is closed immediately."
    public static let maxAuthenticatedSessions: Int = 4
    /// See `maxAuthenticatedSessions`.
    public static let maxPendingSessions: Int = 2

    /// spec §3.0: "Max trusted devices | 20 per host; 10 trusted hosts per client."
    public static let maxTrustedDevicesPerHost: Int = 20
    /// See `maxTrustedDevicesPerHost`.
    public static let maxTrustedHostsPerClient: Int = 10

    /// spec §3.0: "Control message rate | ≤ 200 messages/s per session (token bucket, burst 400);
    /// excess → `rate.limited` then close."
    public static let controlMessageRatePerSecond: Int = 200
    /// See `controlMessageRatePerSecond`.
    public static let controlMessageBurst: Int = 400

    // MARK: - §2.3 / §11.3 Network

    /// Default TCP control port and UDP motion port (same value, same instance). spec §11.3:
    /// "TCP / UDP port | 47800 / 47800 | 1024–65535 (ephemeral fallback) | §2.3".
    public static let defaultTCPPort: Int = 47_800
    /// See `defaultTCPPort`.
    public static let defaultUDPPort: Int = 47_800
    /// spec §11.3: allowed port range including the ephemeral fallback.
    public static let validPortRange: ClosedRange<Int> = 1024...65535

    // MARK: - §3.1.3 / §11.3 QR pairing payload

    /// spec §3.1.3 / §11.3: "Total URL length SHALL be ≤ 512 bytes (fits QR version 15 at ECC-M)".
    public static let qrURLMaxBytes: Int = 512
    /// spec §3.1.3: "`a` ... 1–6 addresses".
    public static let qrMaxAddresses: Int = 6

    // MARK: - §3.1.4 / §11.3 One-time pairing secret

    /// spec §3.1.4: "Generated when the Pairing window opens ... lifetime 60 s".
    public static let pairingSecretByteCount: Int = 16
    /// See `pairingSecretByteCount`.
    public static let pairingSecretLifetimeSeconds: Int = 60
    /// spec §3.1.4: "invalidated ... after 3 failed proofs for that secret".
    public static let pairingSecretMaxFailedAttempts: Int = 3
    /// spec §3.1.4 / FR-DP-004: "Failed pairing attempts are rate-limited to 5 per minute per
    /// source IP".
    public static let pairingRateLimitPerMinutePerIP: Int = 5

    // MARK: - §3.3.2 / §11.3 Address selection / reconnect

    /// spec §3.3.2: candidates are staggered by this interval ("happy-eyeballs").
    public static let addressConnectStaggerMs: Int = 700
    /// spec §3.3.2: "per-candidate timeout 4 s".
    public static let addressPerCandidateTimeoutMs: Int = 4_000
    /// spec §11.3: overall connect timeout across all candidates.
    public static let addressOverallConnectTimeoutMs: Int = 12_000

    /// spec §11.3: "Reconnect backoff | 250, 500, 1000, 2000, 4000 ms cap, ±20 %".
    public static let reconnectBackoffStepsMs: [Int] = [250, 500, 1000, 2000, 4000]
    /// See `reconnectBackoffStepsMs`.
    public static let reconnectBackoffJitterFraction: Double = 0.20
    /// spec §11.3: "Reconnect give-up (foreground) | 10 min".
    public static let reconnectGiveUpForegroundSeconds: Int = 600

    // MARK: - §3.4.6 Heartbeat and session timeout

    /// spec §3.4.6: "Client sends `heartbeat` every 500 ms".
    public static let heartbeatIntervalMs: Int = 500
    /// spec §3.4.6: "no `heartbeat` for 2 000 ms → ... mark the session `stale`".
    public static let sessionStaleTimeoutMs: Int = 2_000
    /// spec §3.4.6: "no heartbeat for 6 000 ms → close TCP".
    public static let sessionCloseTimeoutMs: Int = 6_000

    // MARK: - §3.5.3 / §3.5.5 UDP keys and rotation

    /// spec §3.5.5: "the host additionally rotates when either direction's counter reaches 2³¹".
    public static let udpKeyRotationCounterThreshold: UInt64 = 1 << 31
    /// spec §3.5.5: "or 4 h after issue".
    public static let udpKeyRotationIntervalSeconds: Int = 4 * 3600
    /// spec §3.5.5: "the host keeps accepting the previous `sessionID` for 2 s".
    public static let udpKeyOverlapSeconds: Int = 2
    /// spec §3.5.3: "A sender that reaches counter 2³² SHALL stop sending and request/issue a new
    /// key".
    public static let udpCounterHardLimit: UInt64 = 1 << 32

    // MARK: - §3.5.4 Replay window

    /// spec §3.5.4 / §11.3: "Replay window / stale-apply window | 64 / 8". `W` in the RFC 6479
    /// style sliding window.
    public static let replayWindowSize: Int = 64
    /// spec §3.5.4: "an accepted motion datagram whose counter is more than 8 below the highest
    /// applied counter is not applied".
    public static let motionStaleApplyWindow: Int = 8

    // MARK: - §3.5.6 / §3.6.2 Motion / scroll timing

    /// spec §3.5.6: "if no motion datagram arrives for 100 ms while a stream was active, the host
    /// treats the stream as paused".
    public static let motionPauseGapMs: Int = 100
    /// spec §3.6.2: "No delta for 120 ms while a session is open → behave as `ended`".
    public static let implicitScrollEndMs: Int = 120

    // MARK: - §3.5.7 Coalescing

    /// spec §3.5.7: "at most 2 datagrams may be in flight (send completion not yet called)".
    public static let motionInFlightDatagramCap: Int = 2

    // MARK: - §3.5.8 UDP probe and TCP fallback

    /// spec §3.5.8: "Probe interval, connected | 250 ms (4 Hz)".
    public static let probeIntervalMs: Int = 250
    /// spec §3.5.8: "Probe window | last 12 probes (3 s)".
    public static let probeWindowSize: Int = 12
    /// spec §3.5.8: "Enter fallback | ≥ 11 of 12 unanswered (≥ 90 %) ...".
    public static let probeFallbackLostThreshold: Int = 11
    /// spec §3.5.8: "... or the first 8 probes after connect all unanswered (2 s)".
    public static let probeFallbackInitialUnansweredBurst: Int = 8
    /// spec §3.5.8: "Exit fallback | 5 consecutive probes answered".
    public static let probeRecoveryAnsweredThreshold: Int = 5
    /// spec §3.5.8: "coalesced to ≤ 60 frames/s (≥ 16.7 ms apart ...)".
    public static let tcpFallbackMaxFramesPerSecond: Int = 60
    /// spec §3.5.9: "1 ≤ n ≤ 16" motion payloads per `kind = 0x02` frame.
    public static let motionBatchMaxPayloadsPerFrame: Int = 16

    // MARK: - §5.3.2 / §11.3 Prediction

    /// spec §11.3: "Prediction | off | on/off; ≤ 16 ms". Default off in v1 (§3.5.6).
    public static let predictionDefaultEnabled: Bool = false
    /// See `predictionDefaultEnabled`.
    public static let predictionMaxLookaheadMs: Int = 16

    // MARK: - §5.4 / §3.6.1 Pointer sensitivity, acceleration, scroll

    /// spec §11.3: "Pointer sensitivity | 5 | 1–10 → base 0.6–4.0".
    public static let pointerSensitivityDefault: Int = 5
    /// See `pointerSensitivityDefault`.
    public static let pointerSensitivityRange: ClosedRange<Int> = 1...10
    /// See `pointerSensitivityDefault`.
    public static let pointerSensitivityBaseRange: ClosedRange<Double> = 0.6...4.0

    /// spec §11.3: "Acceleration `a` / `v_ref` | 2.5 / 1500 pt/s | 0, 1.0, 2.5, 4.0".
    public static let accelerationCurveDefaultA: Double = 2.5
    /// See `accelerationCurveDefaultA`.
    public static let accelerationCurveVRefPointsPerSecond: Double = 1500.0
    /// See `accelerationCurveDefaultA`.
    public static let accelerationCurveAllowedValues: [Double] = [0, 1.0, 2.5, 4.0]

    /// spec §3.6.1 / §11.3: "Scroll speed | 5 | 1–10 → 0.5–3.0".
    public static let scrollSpeedDefault: Int = 5
    /// See `scrollSpeedDefault`.
    public static let scrollSpeedRange: ClosedRange<Int> = 1...10
    /// See `scrollSpeedDefault`.
    public static let scrollGainRange: ClosedRange<Double> = 0.5...3.0

    // MARK: - §3.6.3 Momentum

    /// spec §3.6.3 / §11.3: "Momentum τ / min fling / stop threshold / tick | 350 ms / 300 pt/s /
    /// 0.5 px/frame / 60 Hz".
    public static let momentumTauMs: Double = 350
    /// See `momentumTauMs`.
    public static let momentumMinFlingSpeedPointsPerSecond: Double = 300
    /// See `momentumTauMs`.
    public static let momentumStopThresholdPixelsPerFrame: Double = 0.5
    /// See `momentumTauMs`.
    public static let momentumTickHz: Double = 60

    // MARK: - §5.5 / §11.3 Macro limits and timeouts

    /// spec §5.5.1 / §11.3: "Macro limits | 64 total, 6 pages × 12, name 24, sequence 16 steps,
    /// script 8 KB, shell 2 KB, URL 2 KB".
    public static let macroMaxTotal: Int = 64
    /// See `macroMaxTotal`.
    public static let macroMaxPages: Int = 6
    /// See `macroMaxTotal`.
    public static let macroMaxPerPage: Int = 12
    /// See `macroMaxTotal`.
    public static let macroNameMaxLength: Int = 24
    /// See `macroMaxTotal`.
    public static let macroSequenceMaxSteps: Int = 16
    /// spec §5.5.1: `SequenceStep.text` ≤ 256.
    public static let macroSequenceStepTextMaxLength: Int = 256
    /// spec §5.5.1: `interStepDelayMs` 0–2000.
    public static let macroSequenceInterStepDelayRangeMs: ClosedRange<Int> = 0...2000
    /// See `macroMaxTotal`.
    public static let macroScriptMaxBytes: Int = 8_192
    /// See `macroMaxTotal`.
    public static let macroShellCommandMaxBytes: Int = 2_048
    /// See `macroMaxTotal`.
    public static let macroURLMaxBytes: Int = 2_048
    /// spec §5.5.1: `runShortcut(name: String /*≤ 100*/)`.
    public static let macroShortcutNameMaxLength: Int = 100

    /// spec §11.3: "Macro timeouts | sequence 30 s, launchApp 10 s, openURL 5 s, shortcut 60 s,
    /// script/shell 30 s".
    public static let macroSequenceTimeoutSeconds: Int = 30
    /// See `macroSequenceTimeoutSeconds`.
    public static let macroLaunchAppTimeoutSeconds: Int = 10
    /// See `macroSequenceTimeoutSeconds`.
    public static let macroOpenURLTimeoutSeconds: Int = 5
    /// See `macroSequenceTimeoutSeconds`.
    public static let macroShortcutTimeoutSeconds: Int = 60
    /// See `macroSequenceTimeoutSeconds`.
    public static let macroScriptTimeoutSeconds: Int = 30

    // MARK: - §3.4.5 / §11.3 Misc message limits

    /// spec §3.4.5 `text` / §11.3 "Text message max | 16 KB".
    public static let textMessageMaxBytes: Int = 16_384
    /// spec §3.4.5 `settings.textRateCharsPerSec` default / range.
    public static let textRateCharsPerSecDefault: Int = 500
    /// See `textRateCharsPerSecDefault`.
    public static let textRateCharsPerSecRange: ClosedRange<Int> = 50...2000
    /// spec §3.4.5 `settings.doubleClickIntervalMs` default / range.
    public static let doubleClickIntervalMsDefault: Int = 300
    /// See `doubleClickIntervalMsDefault`.
    public static let doubleClickIntervalMsRange: ClosedRange<Int> = 150...600

    /// spec §11.3: "Volume set rate | 20/s".
    public static let volumeSetRateHz: Int = 20
    /// spec §11.3: "Injection caps | motion 250/s, clicks 30/s, keys 60/s, media 20/s".
    public static let injectionCapMotionPerSecond: Int = 250
    /// See `injectionCapMotionPerSecond`.
    public static let injectionCapClicksPerSecond: Int = 30
    /// See `injectionCapMotionPerSecond`.
    public static let injectionCapKeysPerSecond: Int = 60
    /// See `injectionCapMotionPerSecond`.
    public static let injectionCapMediaPerSecond: Int = 20
    /// spec §11.3: "Held-input watchdog | 60 s".
    public static let heldInputWatchdogSeconds: Int = 60

    /// spec §3.4.5 `helloAck.heartbeatMs` default.
    public static let helloAckHeartbeatMsDefault: Int = 500
    /// spec §3.4.5 `helloAck.sessionTimeoutMs` default.
    public static let helloAckSessionTimeoutMsDefault: Int = 2_000
    /// spec §3.4.5 `helloAck.maxTextBytes` default.
    public static let helloAckMaxTextBytesDefault: Int = 16_384
    /// spec §3.4.5 `sessionKey.validForMs`: "14 400 000" (4 hours).
    public static let sessionKeyValidForMsDefault: Int = 14_400_000
}
