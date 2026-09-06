// Tests/AppEnvironmentTests.swift
// `AppEnvironment` wiring with mocks for every cross-module protocol slot, to confirm the DI
// container is genuinely swappable (arch §3.2: "Every protocol has a `Mock*` implementation in
// `Tests/Support`") and that its own owned services construct without a real Keychain/App
// Support directory.

import Testing
import Foundation
@testable import Air_Control

@MainActor
private final class MockConnectionManager: ConnectionManaging {
    var connectionState: ConnectionState = .idle
    var currentHostName: String? = "Mock Mac"
    var connectCallCount = 0
    var disconnectCallCount = 0

    func connect() async { connectCallCount += 1; connectionState = .connected(hostName: "Mock Mac") }
    func disconnect() async { disconnectCallCount += 1; connectionState = .idle }
}

@MainActor
private final class MockMotionPublisher: MotionPublishing {
    var isPublishing = false
}

@MainActor
private final class MockGyroEngine: GyroEngineProviding {
    var isGyroAvailable = true
    var startCallCount = 0
    var stopCallCount = 0
    func start() async { startCallCount += 1 }
    func stop() async { stopCallCount += 1 }
}

@MainActor
private final class MockKeyboardBridge: KeyboardBridging {
    var isHardwarePassthroughActive = false
}

@MainActor
private final class MockMacroStore: MacroStoreProviding {
    var macroCount = 3
    var refreshCallCount = 0
    func refresh() async { refreshCallCount += 1 }
}

@MainActor
private final class MockPairingRouter: PairingRouting {
    var lastRoutedURL: URL?
    func routePairing(url: URL) { lastRoutedURL = url }
}

@MainActor
@Suite struct AppEnvironmentTests {
    private func makeEnvironment() -> (AppEnvironment, MockConnectionManager, MockPairingRouter) {
        let connection = MockConnectionManager()
        let pairingRouter = MockPairingRouter()
        let env = AppEnvironment(
            userSettings: UserSettings(defaults: UserDefaults(suiteName: "AppEnvironmentTests-\(UUID().uuidString)")!),
            keychain: InMemoryKeychainStore(),
            documentStore: DocumentStore(rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("AppEnvironmentTests-\(UUID().uuidString)")),
            connection: connection,
            motion: MockMotionPublisher(),
            gyro: MockGyroEngine(),
            keyboard: MockKeyboardBridge(),
            macros: MockMacroStore(),
            pairingRouter: pairingRouter
        )
        return (env, connection, pairingRouter)
    }

    @Test func defaultInitializerUsesNoOpsAndDoesNotCrash() {
        let env = AppEnvironment()
        #expect(env.connection.connectionState == .idle)
        #expect(env.gyro.isGyroAvailable == false)
        #expect(env.macros.macroCount == 0)
    }

    @Test func mockConnectionIsReachableThroughTheSlot() async {
        let (env, connection, _) = makeEnvironment()
        await env.connection.connect()
        #expect(connection.connectCallCount == 1)
        #expect(env.connection.connectionState == .connected(hostName: "Mock Mac"))
    }

    @Test func pairingRouterReceivesForwardedURL() {
        let (env, _, router) = makeEnvironment()
        let url = URL(string: "aircontrol://pair?v=1")!
        env.pairingRouter.routePairing(url: url)
        #expect(router.lastRoutedURL == url)
    }

    @Test func slotsAreIndependentlySwappable() {
        let (env, _, _) = makeEnvironment()
        #expect(env.gyro.isGyroAvailable == true)
        #expect(env.macros.macroCount == 3)
        env.gyro = NoOpGyroEngine()
        #expect(env.gyro.isGyroAvailable == false)
    }

    @Test func ownedServicesAreConstructedAndUsable() throws {
        let (env, _, _) = makeEnvironment()
        try env.keychain.set(Data("secret".utf8), for: KeychainItem(service: "test", account: "a"))
        let read = try env.keychain.get(KeychainItem(service: "test", account: "a"))
        #expect(read == Data("secret".utf8))
        #expect(env.labs.prediction == false)
        #expect(env.diagnostics.latest == nil)
    }
}
