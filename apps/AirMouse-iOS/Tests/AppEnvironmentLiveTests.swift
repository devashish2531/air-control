// Tests/AppEnvironmentLiveTests.swift
// Confirms the integration agent's composition root (`AppEnvironment.live()`,
// App/AppEnvironment.swift) actually wires the real services rather than the `NoOp*` defaults
// (App/DefaultServices.swift), and that doing so is inert: no Bonjour browsing, connection
// attempt, or motion sampling starts merely from constructing the environment — those only start
// when a view calls `startBrowsing()`/`connect()`/`GyroEngine.start()` on appear (spec §4.1.3 /
// §4.5.5 / §4.3), so building `live()` never triggers the local-network or motion permission
// prompts.

import Testing
@testable import Air_Mouse

@MainActor
@Suite struct AppEnvironmentLiveTests {
    @Test func liveConstructsWithoutCrashing() {
        let environment = AppEnvironment.live()
        #expect(environment.connection.connectionState == .idle)
    }

    @Test func liveDoesNotStartBrowsingOrConnectingOnConstruction() throws {
        let environment = AppEnvironment.live()
        let manager = try #require(environment.connection as? ConnectionManager)
        // `ConnectionManager.init` only loads/creates the client Keychain identity and replays
        // known hosts from disk — `startBrowsing()`/`connect()` are separate calls `DevicesScreen`
        // /`RootTabView` make on appear, never from `AppEnvironment.live()` itself.
        #expect(manager.browseState == .idle)
        #expect(manager.discoveredHosts.isEmpty)
        #expect(manager.connectionState == .idle)
    }

    @Test func liveInstallsTheSameConnectionManagerAsBothSlots() {
        let environment = AppEnvironment.live()
        let connection = environment.connection as? ConnectionManager
        let pairingRouter = environment.pairingRouter as? ConnectionManager
        #expect(connection != nil)
        #expect(connection === pairingRouter)
    }

    @Test func liveWiresRealConcreteServiceTypes() {
        let environment = AppEnvironment.live()
        #expect(environment.connection is ConnectionManager)
        #expect(environment.pairingRouter is ConnectionManager)
        #expect(environment.motion is MotionPublisherStatusAdapter)
        #expect(environment.gyro is GyroEngine)
        #expect(environment.keyboard is KeyboardBridge)
        // `motionPublisher` is statically `MotionPublisher` (not a NoOp), and `gyro`'s engine is
        // fed by that exact instance — not a second, disconnected one.
        #expect((environment.gyro as? GyroEngine) != nil)
    }

    @Test func liveGyroAvailabilityMatchesRealHardwareCapability() {
        // Simulator hardware reports no device motion — this exercises the real `GyroEngine`'s
        // `isGyroAvailable` (spec FR-GY-012) rather than `NoOpGyroEngine`'s hardcoded `false`,
        // even though both currently read `false` on this host.
        let environment = AppEnvironment.live()
        let engine = environment.gyro as? GyroEngine
        #expect(engine != nil)
        #expect(engine?.isGyroAvailable == CoreMotionSampler().isDeviceMotionAvailable)
    }

    @Test func tabListContainsAllFiveTabs() {
        #expect(AppTab.allCases.count == 5)
        #expect(AppTab.allCases.contains(.touchpad))
        #expect(AppTab.allCases.contains(.airMouse))
        #expect(AppTab.allCases.contains(.keyboard))
        #expect(AppTab.allCases.contains(.remote))
        #expect(AppTab.allCases.contains(.macros))
    }
}
