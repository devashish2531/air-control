// spec §5.1.3 "Diagnostics" window and arch §8 "Diagnostics HUD" — the Mac side reads a
// `DiagnosticsSnapshot` published by the inject/net executors (owned by other agents) through a
// lock-guarded copy. This protocol is the minimal read surface this window needs from that publisher.
import Foundation

public struct DiagnosticsSnapshot: Sendable, Equatable, Codable {
    public struct SessionStat: Sendable, Equatable, Codable, Identifiable {
        public var id: String
        public var deviceName: String
        public var motionDatagramRateHz: Double
        public var rttP50Millis: Double
        public var rttP95Millis: Double
        public var droppedCount: Int
        public var replayedCount: Int
        public var staleCount: Int
        public var aeadFailureCount: Int
        public var negotiatedCipher: String
        /// First 8 hex chars only (spec §5.7.3).
        public var peerFingerprintPrefix: String
        public var channel: String

        public init(
            id: String,
            deviceName: String,
            motionDatagramRateHz: Double,
            rttP50Millis: Double,
            rttP95Millis: Double,
            droppedCount: Int,
            replayedCount: Int,
            staleCount: Int,
            aeadFailureCount: Int,
            negotiatedCipher: String,
            peerFingerprintPrefix: String,
            channel: String
        ) {
            self.id = id
            self.deviceName = deviceName
            self.motionDatagramRateHz = motionDatagramRateHz
            self.rttP50Millis = rttP50Millis
            self.rttP95Millis = rttP95Millis
            self.droppedCount = droppedCount
            self.replayedCount = replayedCount
            self.staleCount = staleCount
            self.aeadFailureCount = aeadFailureCount
            self.negotiatedCipher = negotiatedCipher
            self.peerFingerprintPrefix = peerFingerprintPrefix
            self.channel = channel
        }
    }

    public var sessions: [SessionStat]
    public var injectedEventsPerSecond: Double
    public var injectP50Millis: Double
    public var injectP95Millis: Double
    public var generatedAt: Date

    public init(
        sessions: [SessionStat],
        injectedEventsPerSecond: Double,
        injectP50Millis: Double,
        injectP95Millis: Double,
        generatedAt: Date
    ) {
        self.sessions = sessions
        self.injectedEventsPerSecond = injectedEventsPerSecond
        self.injectP50Millis = injectP50Millis
        self.injectP95Millis = injectP95Millis
        self.generatedAt = generatedAt
    }

    public static let empty = DiagnosticsSnapshot(sessions: [], injectedEventsPerSecond: 0, injectP50Millis: 0, injectP95Millis: 0, generatedAt: .distantPast)
}

/// Read-only feed for the Diagnostics window. Counters and timing only — never text, keys, or full IPs
/// (spec §7.4 NFR-PRIV-005: "Diagnostics export contains counters and timing only").
public protocol DiagnosticsSink: Sendable {
    var snapshot: DiagnosticsSnapshot { get async }
}
