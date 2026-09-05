// arch §3.3 "MenuBarExtra app" row: "icon state from SessionManager snapshots; windows opened via
// openWindow". This is the DI container gluing the (protocol-typed) service slots to the SwiftUI shell.
import AirMouseFilters
import Foundation
import Observation

/// App-wide dependency container, held for the app's lifetime and shared read/write via `@Environment` or
/// direct injection into feature view models. Every cross-module service is behind a protocol defined in
/// `ServiceProtocols.swift`, `Features/Diagnostics/DiagnosticsSink.swift`, or `Services/UpdateService` so
/// other agents can substitute real actors without touching this file's shape.
@MainActor
@Observable
public final class AppEnvironment {
    public let launchArguments: LaunchArguments
    public let settings: HostSettings
    public let documentStore: DocumentStore
    public let permissions: PermissionsService
    public let displayTopology: DisplayTopology
    public let hostStateObserver: HostStateObserver
    public let updateService: any UpdateService

    public var hostService: any HostServing
    public var eventInjector: any EventInjecting
    public var macroStore: any MacroStoring
    public var trustStore: any TrustStoring
    public var diagnosticsSink: any DiagnosticsSink

    /// The richer macro CRUD/engine surface (`Services/MacroEngine/MacroEngine+Environment.swift`),
    /// shared with `MacroEditorWindow` once `wireLiveServices()` has run so the menu bar's tiny
    /// `macroStore` slot and the editor read/write the same `MacroStore` instance. `nil` in the
    /// placeholder/preview state (before `wireLiveServices()` / outside `.live`).
    public private(set) var macroFeature: MacroFeature?

    /// Cached, main-actor-synchronous mirror of `hostService.connectedSessions` for menu rendering
    /// (protocol getters are `async`; SwiftUI menu content needs a synchronous value).
    public private(set) var connectedSessions: [ConnectedSessionInfo] = []
    /// Cached mirror of `eventInjector.isPaused`.
    public private(set) var isInputPaused: Bool = false
    public let installSource: InstallSource

    // `nonisolated(unsafe)`: only touched from start/stopBackgroundRefresh and deinit (nonisolated per
    // Swift's default class-deinit rules). `@ObservationIgnored` keeps the `@Observable` macro from
    // re-wrapping storage access in a way that would otherwise make `nonisolated(unsafe)` a no-op.
    @ObservationIgnored
    nonisolated(unsafe) private var refreshTask: Task<Void, Never>?

    // MARK: - Live-wiring internals (`wireLiveServices()` below)

    /// The concrete `EventInjector` behind `eventInjector` once live, kept so
    /// `syncEventInjectorConfiguration()` can call its `update*` methods — not part of the shell's
    /// `EventInjecting` protocol (deliberately minimal, `App/ServiceProtocols.swift`). `nil` until
    /// `wireLiveServices()` runs (placeholder/preview state).
    private var liveEventInjector: EventInjector?
    /// Retained so the real networking stack's per-session actor stays alive for the app's lifetime
    /// (`HostFeature.make`'s return tuple; nothing else in this file needs to call it directly).
    private var sessionManager: SessionManager?

    private struct AccelPrefs: Equatable {
        var sensitivity: Double
        var profile: AccelerationCurve.Profile
    }
    private struct ScrollPrefs: Equatable {
        var speed: Double
        var invertForNatural: Bool
    }
    private var lastAppliedDisplays: DisplayTopologySnapshot?
    private var lastAppliedAccel: AccelPrefs?
    private var lastAppliedScroll: ScrollPrefs?

    public init(
        launchArguments: LaunchArguments = .parse(),
        settings: HostSettings = HostSettings(),
        documentStore: DocumentStore = DocumentStore(),
        permissions: PermissionsService = PermissionsService(),
        displayTopology: DisplayTopology = DisplayTopology(),
        hostService: any HostServing = PlaceholderHostService(),
        eventInjector: any EventInjecting = PlaceholderEventInjector(),
        macroStore: any MacroStoring = PlaceholderMacroStore(),
        trustStore: any TrustStoring = PlaceholderTrustStore(),
        diagnosticsSink: any DiagnosticsSink = PlaceholderDiagnosticsSink(),
        updateService: any UpdateService = GitHubReleasesUpdateChecker(
            owner: "air-mouse",
            repo: "air-mouse",
            currentVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        )
    ) {
        self.launchArguments = launchArguments
        self.settings = settings
        self.documentStore = documentStore
        self.permissions = permissions
        self.displayTopology = displayTopology
        self.hostService = hostService
        self.eventInjector = eventInjector
        self.macroStore = macroStore
        self.trustStore = trustStore
        self.diagnosticsSink = diagnosticsSink
        self.updateService = updateService
        self.installSource = .detect()

        if let overrideLevel = launchArguments.logLevel {
            settings.logLevel = overrideLevel
        }

        // Placeholder provider — `self` isn't fully initialized yet, so the real binding (reading
        // `isInputPaused`, which mirrors the async `eventInjector.isPaused`) is installed right after.
        hostStateObserver = HostStateObserver(
            displayTopology: displayTopology,
            permissions: permissions,
            isPausedProvider: { false }
        )
        hostStateObserver.updatePausedProvider { [weak self] in self?.isInputPaused ?? false }
    }

    /// A placeholder-backed instance for SwiftUI previews and tests that don't want to spin up real
    /// networking/injection actors (no Accessibility prompt, no listening socket, no `Macros.json`
    /// I/O). Identical to the memberwise initializer with no arguments; given a discoverable, named
    /// spelling alongside `.live` so call sites read as "which world do I want".
    public static var preview: AppEnvironment { AppEnvironment() }

    /// Builds an `AppEnvironment` with every service slot backed by the real implementation: real
    /// `DocumentStore`/`HostSettings`/`PermissionsService`/`DisplayTopology` (dependency order per the
    /// assignment), then `wireLiveServices()` for the `EventInjector`/`MacroFeature`/`HostFeature`
    /// stack. Awaits the whole wiring before returning, so callers (tests included) see non-placeholder
    /// services immediately.
    public static func live(launchArguments: LaunchArguments = .parse()) async -> AppEnvironment {
        let environment = AppEnvironment(
            launchArguments: launchArguments,
            settings: HostSettings(),
            documentStore: DocumentStore(),
            permissions: PermissionsService(),
            displayTopology: DisplayTopology()
        )
        await environment.wireLiveServices()
        return environment
    }

    /// Swaps every placeholder service slot for the real implementation, in place: `KeycodeMapper` →
    /// `EventInjector(poster: CGEventPoster(), ...)` → `MacroFeature.make` → `HostFeature.make`. Mutates
    /// this instance's `var` slots (`hostService`, `eventInjector`, `macroStore`, `trustStore`,
    /// `diagnosticsSink`) rather than returning a new object, so the single `@Observable` instance
    /// already bound into every SwiftUI scene (`AirMouseHelperApp`'s `@State`) stays the one every
    /// window reads — no scene needs to swap references. Idempotent: a second call is a no-op.
    ///
    /// Called by `AppEnvironment.live` (tests) and by `MenuBarIconLabel`'s launch-once `.task` (the
    /// running app, which starts with the placeholder-backed default `@State` value so the menu bar
    /// icon renders instantly, then upgrades in place).
    func wireLiveServices() async {
        guard liveEventInjector == nil else { return }

        // spec §5.3.6/§5.4: real CGEvent posting + keycode mapping + the Mac's current display
        // arrangement (so `DisplayClamp` starts correct, not `.empty`).
        let keycodeMapper = KeycodeMapper()
        let injector = EventInjector(
            poster: CGEventPoster(),
            keycodeMapper: keycodeMapper,
            displays: displayTopology.snapshot
        )
        liveEventInjector = injector
        eventInjector = injector

        // `MacroFeature.make` needs the whole (`@MainActor`) `AppEnvironment` only for
        // `environment.documentStore` (`Services/MacroEngine/MacroEngine+Environment.swift`); `self` is
        // fully initialized by the time this instance method runs, so passing `self` here is safe
        // (unlike from `init`).
        let macroFeature = await MacroFeature.make(environment: self, keyEmitter: injector)
        self.macroFeature = macroFeature
        macroStore = macroFeature.store

        let hostFeatureEnvironment = HostFeatureEnvironment(
            documentStore: documentStore,
            launchArguments: launchArguments,
            hostStateSnapshotProvider: { [hostStateObserver] in
                await MainActor.run { hostStateObserver.snapshot }
            },
            globalScriptsEnabledProvider: { [settings] in
                await MainActor.run { settings.allowScriptsGlobal }
            },
            hostNameProvider: {
                // Mirrors `HostSettings.deviceDisplayName`'s UserDefaults key/default
                // (`Support/Settings.swift`) rather than calling the `@MainActor` accessor: this
                // provider's signature is a synchronous, nonisolated `@Sendable () -> String` (it may
                // be invoked from `SessionManager`'s own executor), and `UserDefaults` reads are
                // thread-safe.
                UserDefaults.standard.string(forKey: "am.helper.deviceDisplayName") ?? Host.current().localizedName ?? "Mac"
            }
        )
        let hostFeature = HostFeature.make(
            environment: hostFeatureEnvironment,
            injector: injector,
            macroEngine: macroFeature.engine,
            macroStore: macroFeature.store
        )
        hostService = hostFeature.hostServer
        trustStore = hostFeature.trustStore
        sessionManager = hostFeature.sessionManager
        diagnosticsSink = AppDiagnosticsSink(hostService: hostFeature.hostServer)

        await syncEventInjectorConfiguration()
    }

    /// Starts the ~1 Hz polling loop that mirrors the async protocol services into synchronous,
    /// `@Observable` properties the menu and windows read directly. Call once from `AirMouseHelperApp.init`.
    public func startBackgroundRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshNow()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    public func stopBackgroundRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    public func refreshNow() async {
        connectedSessions = await hostService.connectedSessions
        isInputPaused = await eventInjector.isPaused
        hostStateObserver.refresh()
        await syncEventInjectorConfiguration()
    }

    /// Menu "Pause input" checkbox (spec §5.3.10).
    public func toggleInputPaused() async {
        if isInputPaused {
            await eventInjector.resume()
        } else {
            await eventInjector.pause()
        }
        isInputPaused = await eventInjector.isPaused
        hostStateObserver.refresh()
    }

    /// Pushes `DisplayTopology`/`HostSettings` pointer & scroll preference changes into the live
    /// `EventInjector`, diffing against the last-applied values so unchanged ticks are no-ops. A no-op
    /// before `wireLiveServices()` runs (`liveEventInjector` is `nil` in the placeholder/preview state).
    private func syncEventInjectorConfiguration() async {
        guard let liveEventInjector else { return }

        let displays = displayTopology.snapshot
        if displays != lastAppliedDisplays {
            lastAppliedDisplays = displays
            await liveEventInjector.updateDisplays(displays)
        }

        let accel = currentAccelerationPrefs()
        if accel != lastAppliedAccel {
            lastAppliedAccel = accel
            await liveEventInjector.updateAcceleration(sensitivity: accel.sensitivity, profile: accel.profile)
        }

        let scroll = currentScrollPrefs()
        if scroll != lastAppliedScroll {
            lastAppliedScroll = scroll
            await liveEventInjector.updateScroll(speed: scroll.speed, invertForNatural: scroll.invertForNatural)
        }
    }

    /// `HostSettings.pointerAccelerationDefault`/`.pointerSensitivityDefault` are documented (
    /// `Support/Settings.swift`) as 0...1 multipliers ("1.0 = system default curve") — a deviation the
    /// Preferences agent noted since arch §6.2 has no key for them — while `AccelerationCurve` (spec
    /// §5.4) wants a continuous sensitivity in 1...10 (default 5) and a discrete `Profile`. This maps
    /// the multiplier onto both so the documented defaults line up exactly at 1.0 → sensitivity 5,
    /// `.default` profile.
    private func currentAccelerationPrefs() -> AccelPrefs {
        let sensitivity = min(10, max(1, 5 * settings.pointerSensitivityDefault))
        let profile: AccelerationCurve.Profile
        switch settings.pointerAccelerationDefault {
        case ..<0.25: profile = .off
        case ..<0.75: profile = .precise
        case ..<1.25: profile = .default
        default: profile = .fast
        }
        return AccelPrefs(sensitivity: sensitivity, profile: profile)
    }

    /// `HostSettings` has no dedicated scroll-speed key (only `naturalScrollOverride`), so `ScrollGain`'s
    /// own spec-default speed (5) is used; only the natural-scroll sign is driven by the preference,
    /// falling back to the live system preference (`HostStateObserver.snapshot.naturalScrollEnabled`)
    /// when the override is `.system`.
    private func currentScrollPrefs() -> ScrollPrefs {
        let invertForNatural: Bool
        switch settings.naturalScrollOverride {
        case .system: invertForNatural = hostStateObserver.snapshot.naturalScrollEnabled
        case .natural: invertForNatural = true
        case .inverted: invertForNatural = false
        }
        return ScrollPrefs(speed: ScrollGain().scrollSpeed, invertForNatural: invertForNatural)
    }

    deinit {
        refreshTask?.cancel()
    }
}
