// App/AppEnvironment.swift
// DI container (arch §3.2 "Dependency injection"). Built once in `AirMouseApp` and injected
// through the SwiftUI environment. View models are constructed by views from the environment and
// never construct services themselves.
//
// Deviation from arch's literal wording ("a plain `struct`"): this is a `@MainActor @Observable
// final class` per this agent's assignment, so that mutating a cross-module slot (e.g. swapping
// the `NoOp*` default for a real `ConnectionManager` once the Connection agent lands) is visible
// to every view holding a reference, without threading a new struct value through the view tree.

import SwiftUI
import Observation

@MainActor
@Observable
public final class AppEnvironment {
    // MARK: Services this module owns

    public let userSettings: UserSettings
    public let labs: Labs
    public let haptics: any HapticsService
    public let keychain: any KeychainStore
    public let documentStore: DocumentStore
    public let idleTimer: IdleTimer
    public let diagnostics: DiagnosticsModel

    // MARK: Cross-module slots (owned by other agents; default to no-ops until wired)

    public var connection: any ConnectionManaging
    public var motion: any MotionPublishing
    public var gyro: any GyroEngineProviding
    public var keyboard: any KeyboardBridging
    public var macros: any MacroStoreProviding
    public var pairingRouter: any PairingRouting

    // MARK: Sinks (owned by the Connection agent; stored here once `live()` wires them so views
    // don't have to downcast `connection`/`motion` themselves to reach the write side — see
    // `ConnectionManager+Environment.swift`'s `ConnectionFeature.Bundle`).

    public var controlSink: any ControlMessageSink
    public var remoteSink: any RemoteCommandSink
    public var motionPublisher: MotionPublisher

    public init(
        userSettings: UserSettings = UserSettings(),
        labs: Labs = Labs(),
        haptics: any HapticsService = UIKitHapticsService(),
        keychain: any KeychainStore = SecureKeychainStore(),
        documentStore: DocumentStore = DocumentStore(),
        idleTimer: IdleTimer = IdleTimer(),
        diagnostics: DiagnosticsModel = DiagnosticsModel(),
        connection: any ConnectionManaging = NoOpConnectionManager(),
        motion: any MotionPublishing = NoOpMotionPublisher(),
        gyro: any GyroEngineProviding = NoOpGyroEngine(),
        keyboard: any KeyboardBridging = NoOpKeyboardBridge(),
        macros: any MacroStoreProviding = NoOpMacroStore(),
        pairingRouter: any PairingRouting = NoOpPairingRouter(),
        controlSink: any ControlMessageSink = NoOpControlMessageSink(),
        remoteSink: any RemoteCommandSink = NoOpRemoteCommandSink(),
        motionPublisher: MotionPublisher = MotionPublisher(sink: NoOpMotionDatagramSink())
    ) {
        self.userSettings = userSettings
        self.labs = labs
        self.haptics = haptics
        self.keychain = keychain
        self.documentStore = documentStore
        self.idleTimer = idleTimer
        self.diagnostics = diagnostics
        self.connection = connection
        self.motion = motion
        self.gyro = gyro
        self.keyboard = keyboard
        self.macros = macros
        self.pairingRouter = pairingRouter
        self.controlSink = controlSink
        self.remoteSink = remoteSink
        self.motionPublisher = motionPublisher
    }
}

/// Preview/test-friendly in-memory environment: `SecureKeychainStore` needs a real Keychain
/// (unavailable in SwiftUI previews and some test hosts), so this swaps it and the document
/// store's root for safe, ephemeral equivalents.
public extension AppEnvironment {
    @MainActor
    static func preview() -> AppEnvironment {
        AppEnvironment(
            keychain: InMemoryKeychainStore(),
            documentStore: DocumentStore(rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("AirMousePreview-\(UUID().uuidString)"))
        )
    }
}

/// The app's real composition root (arch §3.2). Builds every owned service, then the
/// cross-module slots in dependency order: `ConnectionFeature.make(environment:)` needs the
/// environment's owned services to already exist, and `GyroEngine`/`AirMouseFeature` need the
/// real `MotionPublisher` (not just its `MotionPublishing` facade) to be in place first.
///
/// Deliberately does *not* start Bonjour browsing, connect a session, or start gyro sampling —
/// `ConnectionManager.init` only loads/creates the client Keychain identity and replays known
/// hosts from disk (no `Network` traffic), and `GyroEngine.init` only reads
/// `CMMotionManager().isDeviceMotionAvailable` (a capability flag, not a permission request).
/// Browsing/sampling start only when a view calls `startBrowsing()`/`connect()`/`start()` on
/// appear, so constructing `live()` alone never triggers the local-network or motion permission
/// prompts (verified by `Tests/AppEnvironmentLiveTests.swift`).
public extension AppEnvironment {
    @MainActor
    static func live() -> AppEnvironment {
        let userSettings = UserSettings()
        let documentStore = DocumentStore()
        let keychain = SecureKeychainStore()
        let haptics = UIKitHapticsService()
        let diagnostics = DiagnosticsModel()

        let environment = AppEnvironment(
            userSettings: userSettings,
            haptics: haptics,
            keychain: keychain,
            documentStore: documentStore,
            diagnostics: diagnostics
        )

        // Connection (spec §3.2.1 / §4.5): one `ConnectionManager` installed as both the
        // `ConnectionManaging` and `PairingRouting` slots, per `ConnectionFeature`'s own doc
        // comment.
        let bundle = ConnectionFeature.make(environment: environment)
        environment.connection = bundle.manager
        environment.pairingRouter = bundle.manager
        environment.controlSink = bundle.controlSink
        environment.remoteSink = bundle.remoteSink

        // Motion (spec §3.5.7): the real `MotionPublisher` actor feeds `Diagnostics` and hands
        // finished datagrams to the Connection agent's sink; `MotionPublisherStatusAdapter` is
        // the `@MainActor` facade the shell's `MotionPublishing` slot needs (an actor cannot
        // itself conform to that `@MainActor` protocol).
        let motionPublisher = MotionPublisher(sink: bundle.motionSink, diagnostics: diagnostics)
        environment.motionPublisher = motionPublisher
        environment.motion = MotionPublisherStatusAdapter(publisher: motionPublisher)

        // Gyro (spec §4.3, FR-GY-012): real availability gates the Air Mouse tab in
        // `RootTabView`. Mirrors the settings `AirMouseFeature.makeViewModel` would use if it had
        // to construct the engine itself, so behavior is identical whichever constructs it first.
        let localSettings = AirMouseLocalSettings()
        let gyroSnapshot = userSettings.snapshot.gyro
        environment.gyro = GyroEngine(
            sink: motionPublisher,
            settings: GyroEngineSettings(
                sensitivity: Double(gyroSnapshot.sensitivity),
                smoothingSlider: Double(gyroSnapshot.smoothing),
                deadZoneDegPerSec: gyroSnapshot.deadZoneDegreesPerSecond,
                clutchMode: localSettings.clutchMode,
                recenterMode: localSettings.recenterMode,
                isOrientationLocked: localSettings.isOrientationLocked
            )
        )

        // Keyboard (spec §4.4): wraps the Connection agent's `KeyboardEventSink` in the
        // `KeyboardBridging` facade `KeyboardScreen`/iPad hardware passthrough expect.
        environment.keyboard = KeyboardFeature.makeBridge(sink: bundle.keyboardSink)

        // `UserSettings` → live session: `ConnectionManager.observeSettingsChanges()` already
        // pushes `sendSettings` on every snapshot change once a session exists (see
        // `ConnectionManager.swift`), so no separate `controlSink.sendSettings(...)` observer is
        // added here — that would double-send every settings change.
        return environment
    }
}

// MARK: - Environment key

private struct AppEnvironmentKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue = AppEnvironment()
}

public extension EnvironmentValues {
    var appEnvironment: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
