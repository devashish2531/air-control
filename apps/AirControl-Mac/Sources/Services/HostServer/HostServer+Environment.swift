// HostFeature — wire-up point for the integration agent (assignment §9): swaps
// `PlaceholderHostService`/`PlaceholderTrustStore` in `AppEnvironment` for the real networking
// stack built in this directory. Deliberately does not take the whole (`@MainActor`) `AppEnvironment`
// itself — every value it needs is passed explicitly so this file has no actor-isolation coupling to
// the app shell.
import AirControlCore
import AirControlCrypto
import AirControlProtocol
import Foundation

/// Everything `HostFeature.make` needs from the app shell's environment, gathered into one value so
/// the call site reads as `HostFeature.make(environment: .init(...), injector:, macroEngine:,
/// macroStore:)`. Construct this from `AppEnvironment` (main actor) and hop once.
public struct HostFeatureEnvironment: Sendable {
    public var documentStore: DocumentStore
    public var launchArguments: LaunchArguments
    /// Reads the Mac's current display/pause/accessibility/frontmost-app snapshot (spec §5.3.8);
    /// typically `{ await MainActor.run { hostStateObserver.snapshot } }`.
    public var hostStateSnapshotProvider: @Sendable () async -> HostStateSnapshot
    /// Reads `HostSettings.allowScriptsGlobal` (spec §5.5.5); typically
    /// `{ await MainActor.run { settings.allowScriptsGlobal } }`.
    public var globalScriptsEnabledProvider: @Sendable () async -> Bool
    /// The Mac's display name shown to phones (spec §3.1.1's `Host.current().localizedName`,
    /// or `HostSettings.deviceDisplayName`).
    public var hostNameProvider: @Sendable () -> String
    public var helperVersion: String

    public init(
        documentStore: DocumentStore,
        launchArguments: LaunchArguments,
        hostStateSnapshotProvider: @escaping @Sendable () async -> HostStateSnapshot,
        globalScriptsEnabledProvider: @escaping @Sendable () async -> Bool,
        hostNameProvider: @escaping @Sendable () -> String,
        helperVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    ) {
        self.documentStore = documentStore
        self.launchArguments = launchArguments
        self.hostStateSnapshotProvider = hostStateSnapshotProvider
        self.globalScriptsEnabledProvider = globalScriptsEnabledProvider
        self.hostNameProvider = hostNameProvider
        self.helperVersion = helperVersion
    }
}

public enum HostFeature {
    /// Builds the full networking stack: identity + Bonjour + TLS listener (`HostServer`), the
    /// trusted-device store (`TrustStore`), and per-session wiring (`SessionManager`). The caller
    /// (integration agent) assigns the first two into `AppEnvironment.hostService`/`.trustStore`
    /// and calls `hostServer.start()` once the rest of `AppEnvironment` is ready; `SessionManager`
    /// needs no further wiring beyond what this returns.
    ///
    /// `--loopback` (assignment §8, and the coordinator's follow-up contract): when
    /// `environment.launchArguments.loopback` is set, `injector` is **not** used — a fresh
    /// `EventInjector` backed by `RecordingEventPoster` is built instead, its posted events are
    /// drained to the JSON-lines file at `$AIRCONTROL_LOOPBACK_LOG` (one object per line: `kind`,
    /// `location`, `deltaX`, `deltaY`, `buttonNumber`, `clickState`, `scrollWheel1`, `scrollWheel2`,
    /// `scrollPhase`, `keycode`, `unicodeString`, `nxKeyType`, `isKeyDown`, `timestamp`), and
    /// `HostServer` binds TCP/UDP to ephemeral loopback-only ports, printing
    /// `AIRCONTROL_TCP_PORT=<n>` / `AIRCONTROL_UDP_PORT=<n>` / `AIRCONTROL_PAIR_URL=<url>` to stdout (each
    /// flushed) once `start()` completes, opening the pairing window immediately and keeping it open
    /// (auto-regenerating) until a device pairs.
    public static func make(
        environment: HostFeatureEnvironment,
        injector: EventInjector,
        macroEngine: MacroEngine,
        macroStore: any MacroStoreProviding
    ) -> (hostServer: HostServer, trustStore: TrustStore, sessionManager: SessionManager) {
        let trustStore = TrustStore(documentStore: environment.documentStore)
        let pairingService = PairingService()
        let udpHub = NWUDPHub()
        let loopback = environment.launchArguments.loopback

        let effectiveInjector: EventInjector
        let recordingPoster: RecordingEventPoster?
        if loopback {
            let poster = RecordingEventPoster()
            effectiveInjector = EventInjector(poster: poster)
            recordingPoster = poster
        } else {
            effectiveInjector = injector
            recordingPoster = nil
        }

        let loopbackLogURL: URL? = {
            guard loopback, let path = ProcessInfo.processInfo.environment["AIRCONTROL_LOOPBACK_LOG"] else { return nil }
            return URL(fileURLWithPath: path)
        }()

        let sessionManager = SessionManager(
            eventInjector: effectiveInjector,
            macroEngine: macroEngine,
            macroStore: macroStore,
            trustStore: trustStore,
            pairingService: pairingService,
            udpHub: udpHub,
            hostStateSnapshotProvider: environment.hostStateSnapshotProvider,
            globalScriptsEnabledProvider: environment.globalScriptsEnabledProvider,
            helperVersion: environment.helperVersion,
            recordingPoster: recordingPoster,
            loopbackLogURL: loopbackLogURL
        )

        let serverSettings = HostServerSettings(
            // Dev convenience (`--tcp-port`/`--udp-port`, `LaunchArguments.swift`): lets a second,
            // throwaway copy of the helper bind to alternate fixed ports instead of the real one's
            // default, so it can be launched and torn down without disturbing an already-running
            // helper other tests may depend on.
            tcpPort: loopback ? 0 : (environment.launchArguments.tcpPort ?? UInt16(ProtocolConstants.defaultTCPPort)),
            udpPort: loopback ? 0 : (environment.launchArguments.udpPort ?? UInt16(ProtocolConstants.defaultUDPPort)),
            loopback: loopback,
            documentStore: environment.documentStore,
            hostNameProvider: environment.hostNameProvider
        )
        let hostServer = HostServer(
            settings: serverSettings,
            trustStore: trustStore,
            pairingService: pairingService,
            sessionManager: sessionManager,
            udpHub: udpHub
        )

        // spec §5.6: revoking a device closes any live session for it within 1 s.
        Task {
            await trustStore.setOnRevoked { fingerprint in
                await sessionManager.closeSession(fingerprint: fingerprint, reason: .revoked)
            }
        }

        return (hostServer, trustStore, sessionManager)
    }
}
