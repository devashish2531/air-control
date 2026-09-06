// Tests for `MacroEngine`'s script gating (spec §5.5.5) and non-script execution (spec §5.5.4).
import Testing
@testable import Air_Control
import AirControlProtocol
import Foundation

@Suite struct MacroEngineTests {
    private func shellMacro(name: String = "Deploy") -> Macro {
        Macro(name: name, icon: "hammer.fill", action: .shellCommand(command: "echo hi"), page: 0, order: 0)
    }

    private func keyComboMacro(name: String = "Combo", requiresConfirmation: Bool = false) -> Macro {
        Macro(
            name: name,
            icon: "command",
            action: .keyCombo(modifiers: [.command], keyCode: VirtualKey.kVK_ANSI_A, keyLabel: "⌘A"),
            page: 0,
            order: 0,
            requiresConfirmation: requiresConfirmation
        )
    }

    // MARK: Script gating matrix (spec §5.5.5: global toggle × per-device flag × confirmed)

    @Test(arguments: [
        (global: true, device: true, confirmed: true, expectOK: true),
        (global: true, device: true, confirmed: false, expectOK: false),
        (global: true, device: false, confirmed: true, expectOK: false),
        (global: true, device: false, confirmed: false, expectOK: false),
        (global: false, device: true, confirmed: true, expectOK: false),
        (global: false, device: true, confirmed: false, expectOK: false),
        (global: false, device: false, confirmed: true, expectOK: false),
        (global: false, device: false, confirmed: false, expectOK: false),
    ])
    func scriptGatingMatrix(_ scenario: (global: Bool, device: Bool, confirmed: Bool, expectOK: Bool)) async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MacroStore(documentStore: DocumentStore(baseDirectory: dir))
        let macro = shellMacro()
        _ = await store.list() // bootstrap
        try await store.create(macro)

        let executor = MockMacroActionExecutor()
        await executor.setOutcome(.success("done"))
        let engine = MacroEngine(store: store, executor: executor)

        let result = await engine.invoke(
            MacroInvoke(id: macro.id, confirmed: scenario.confirmed),
            from: "device-1",
            deviceAllowsScripts: scenario.device,
            globalScriptsEnabled: scenario.global
        )

        if scenario.expectOK {
            #expect(result.ok)
            #expect(result.code == .ok)
            #expect(await executor.executedActions.count == 1)
        } else {
            #expect(!result.ok)
            #expect(await executor.executedActions.isEmpty)
            if !scenario.confirmed, scenario.global, scenario.device {
                #expect(result.code == .confirmationRequired)
            } else if !scenario.global || !scenario.device {
                #expect(result.code == .blockedByPolicy)
            }
        }
    }

    // MARK: Non-script kinds are unaffected by script policy

    @Test func nonScriptMacroIgnoresScriptPolicyToggles() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MacroStore(documentStore: DocumentStore(baseDirectory: dir))
        let macro = keyComboMacro()
        _ = await store.list()
        try await store.create(macro)

        let executor = MockMacroActionExecutor()
        await executor.setOutcome(.success(""))
        let engine = MacroEngine(store: store, executor: executor)

        // Neither the global toggle nor the per-device flag is on, yet a plain key combo still runs —
        // §5.5.5's gate only applies to script kinds.
        let result = await engine.invoke(
            MacroInvoke(id: macro.id, confirmed: true),
            from: "device-1",
            deviceAllowsScripts: false,
            globalScriptsEnabled: false
        )
        #expect(result.ok)
        #expect(result.code == .ok)
        #expect(await executor.executedActions.count == 1)
    }

    @Test func nonScriptMacroWithRequiresConfirmationStillNeedsConfirmed() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MacroStore(documentStore: DocumentStore(baseDirectory: dir))
        let macro = keyComboMacro(requiresConfirmation: true)
        _ = await store.list()
        try await store.create(macro)

        let executor = MockMacroActionExecutor()
        let engine = MacroEngine(store: store, executor: executor)

        let result = await engine.invoke(
            MacroInvoke(id: macro.id, confirmed: false),
            from: "device-1",
            deviceAllowsScripts: false,
            globalScriptsEnabled: false
        )
        #expect(result.code == .confirmationRequired)
        #expect(await executor.executedActions.isEmpty)
    }

    @Test func unknownMacroIDReturnsNotFound() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MacroStore(documentStore: DocumentStore(baseDirectory: dir))
        _ = await store.list()

        let executor = MockMacroActionExecutor()
        let engine = MacroEngine(store: store, executor: executor)

        let result = await engine.invoke(
            MacroInvoke(id: UUID(), confirmed: true),
            from: "device-1",
            deviceAllowsScripts: true,
            globalScriptsEnabled: true
        )
        #expect(result.code == .notFound)
        #expect(!result.ok)
    }

    @Test func secondConcurrentScriptIsRejectedWhileOneIsRunning() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MacroStore(documentStore: DocumentStore(baseDirectory: dir))
        let macroA = shellMacro(name: "Slow One")
        let macroB = shellMacro(name: "Slow Two")
        _ = await store.list()
        try await store.create(macroA)
        try await store.create(macroB)

        let executor = SlowMockMacroActionExecutor(delay: .milliseconds(300))
        let engine = MacroEngine(store: store, executor: executor)

        async let first = engine.invoke(
            MacroInvoke(id: macroA.id, confirmed: true),
            from: "device-1",
            deviceAllowsScripts: true,
            globalScriptsEnabled: true
        )
        try await Task.sleep(for: .milliseconds(50)) // let `first` claim the lock
        let second = await engine.invoke(
            MacroInvoke(id: macroB.id, confirmed: true),
            from: "device-1",
            deviceAllowsScripts: true,
            globalScriptsEnabled: true
        )

        #expect(second.code == .failed)
        #expect(second.message == "Another script is running")
        let firstResult = await first
        #expect(firstResult.ok)
    }

    @Test func timedOutExecutionMapsToTimeoutCode() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MacroStore(documentStore: DocumentStore(baseDirectory: dir))
        let macro = shellMacro()
        _ = await store.list()
        try await store.create(macro)

        let executor = MockMacroActionExecutor()
        await executor.setOutcome(.timeout("took too long"))
        let engine = MacroEngine(store: store, executor: executor)

        let result = await engine.invoke(
            MacroInvoke(id: macro.id, confirmed: true),
            from: "device-1",
            deviceAllowsScripts: true,
            globalScriptsEnabled: true
        )
        #expect(result.code == .timeout)
        #expect(!result.ok)
    }
}

private extension MockMacroActionExecutor {
    func setOutcome(_ outcome: MacroExecutionOutcome) {
        outcomeToReturn = outcome
    }
}

/// A `MacroActionExecuting` that sleeps before returning, so tests can assert on the
/// one-concurrent-process lock (spec §7.6) without racing a real subprocess.
private actor SlowMockMacroActionExecutor: MacroActionExecuting {
    let delay: Duration
    init(delay: Duration) { self.delay = delay }

    func execute(_ action: MacroAction) async -> MacroExecutionOutcome {
        try? await Task.sleep(for: delay)
        return .success("done")
    }
}
