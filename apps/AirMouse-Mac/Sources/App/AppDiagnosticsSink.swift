// Small aggregator the integration task's `AppEnvironment.wireLiveServices()` uses for the
// `diagnosticsSink` slot (`Features/Diagnostics/DiagnosticsSink.swift`). Neither `HostServer` nor
// `SessionManager` (owned by the networking agent) publish a `DiagnosticsSnapshot` yet — only the
// shell's tiny `HostServing.connectedSessions` (`App/ServiceProtocols.swift`) — so this reports that
// list with the per-session/global counters zeroed rather than leaving the Diagnostics window on the
// inert `PlaceholderDiagnosticsSink`. Replace this with a direct `SessionManager`/`EventInjector`
// counters feed once those agents publish one (spec §7.4 NFR-PRIV-005: counters and timing only).
import Foundation

actor AppDiagnosticsSink: DiagnosticsSink {
    private let hostService: any HostServing

    init(hostService: any HostServing) {
        self.hostService = hostService
    }

    var snapshot: DiagnosticsSnapshot {
        get async {
            let sessions = await hostService.connectedSessions
            let sessionStats = sessions.map { session in
                DiagnosticsSnapshot.SessionStat(
                    id: session.id,
                    deviceName: session.deviceName,
                    motionDatagramRateHz: 0,
                    rttP50Millis: Double(session.latencyMillis ?? 0),
                    rttP95Millis: Double(session.latencyMillis ?? 0),
                    droppedCount: 0,
                    replayedCount: 0,
                    staleCount: 0,
                    aeadFailureCount: 0,
                    negotiatedCipher: "",
                    peerFingerprintPrefix: "",
                    channel: ""
                )
            }
            return DiagnosticsSnapshot(
                sessions: sessionStats,
                injectedEventsPerSecond: 0,
                injectP50Millis: 0,
                injectP95Millis: 0,
                generatedAt: Date()
            )
        }
    }
}
