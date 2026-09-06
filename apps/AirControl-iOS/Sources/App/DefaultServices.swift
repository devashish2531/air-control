// App/DefaultServices.swift
// Trivial stand-ins for the cross-module protocol slots in ServiceProtocols.swift, so the app
// builds, runs, and previews standalone before the Connection/Motion/Gyro/Keyboard/Macros/
// Pairing agents' concrete types land. `AppEnvironment`'s default initializer uses these; a real
// implementation replaces the corresponding `var` (they're `var`, not `let`) once available.

import Foundation
import Observation

@MainActor
@Observable
public final class NoOpConnectionManager: ConnectionManaging {
    public var connectionState: ConnectionState = .idle
    public var currentHostName: String? { nil }
    public init() {}
    public func connect() async { Log.net.notice("NoOpConnectionManager.connect() — no Connection agent wired yet") }
    public func disconnect() async {}
}

@MainActor
@Observable
public final class NoOpMotionPublisher: MotionPublishing {
    public var isPublishing: Bool = false
    public init() {}
}

@MainActor
@Observable
public final class NoOpGyroEngine: GyroEngineProviding {
    public var isGyroAvailable: Bool = false
    public init() {}
    public func start() async {}
    public func stop() async {}
}

@MainActor
@Observable
public final class NoOpKeyboardBridge: KeyboardBridging {
    public var isHardwarePassthroughActive: Bool = false
    public init() {}
}

@MainActor
@Observable
public final class NoOpMacroStore: MacroStoreProviding {
    public var macroCount: Int = 0
    public init() {}
    public func refresh() async {}
}

@MainActor
public final class NoOpPairingRouter: PairingRouting {
    public init() {}
    public func routePairing(url: URL) {
        Log.deepLink.notice("NoOpPairingRouter received \(url.absoluteString, privacy: .public) — no Pairing agent wired yet")
    }
}
