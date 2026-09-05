// Tests/MacrosModelTests.swift
// `MacrosModel` sync/caching (spec §5.5.6, FR-MC-009), the script-kind confirmation gate
// (spec §5.5.5), and `macroResult` → spec §9 error-copy mapping, all against a
// `FakeRemoteCommandSink` (no real Connection agent needed).

import Testing
import Foundation
import AirMouseProtocol
@testable import Air_Mouse

@MainActor
private final class FakeMacrosSink: RemoteCommandSink {
    var frontmostAppName: String?
    var scriptsAllowedOnHost: Bool = true

    var macroListResult: Result<[Macro], Error> = .success([])
    private(set) var requestMacroListCallCount = 0

    var invokeMacroOutcome: MacroInvokeOutcome = MacroInvokeOutcome(code: .ok)
    var invokeMacroError: Error?
    private(set) var invokeMacroCalls: [MacroInvokeCall] = []

    func sendMediaKey(_ key: MediaKey) {}
    func sendShortcut(virtualKey: UInt16, modifiers: KeyModifiers) {}

    func invokeMacro(id: UUID, confirmed: Bool) async throws -> MacroInvokeOutcome {
        invokeMacroCalls.append(MacroInvokeCall(id: id, confirmed: confirmed))
        if let invokeMacroError { throw invokeMacroError }
        return invokeMacroOutcome
    }

    func requestMacroList() async throws -> [Macro] {
        requestMacroListCallCount += 1
        return try macroListResult.get()
    }
}

private struct StubError: Error {}

private func makeMacro(
    name: String = "Test Macro",
    action: MacroAction = .keyCombo(modifiers: [.command], keyCode: VirtualKey.kVK_ANSI_C, keyLabel: "⌘C"),
    page: Int = 0,
    order: Int = 0,
    requiresConfirmation: Bool = false
) -> Macro {
    Macro(name: name, icon: "star", action: action, page: page, order: order, requiresConfirmation: requiresConfirmation)
}

private func makeStore() -> DocumentStore {
    DocumentStore(rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("MacrosModelTests-\(UUID().uuidString)"))
}

@MainActor
private func makeHaptics() -> UIKitHapticsService {
    UIKitHapticsService(isHapticsEnabled: true, isSoundEnabled: false, supportsHaptics: false)
}

/// Polls `predicate` on the main actor until it is true or `timeout` elapses, since `MacrosModel`
/// kicks off its initial cache-load/sync as a detached `Task` rather than blocking `init`.
@MainActor
private func waitUntil(timeout: Duration = .seconds(2), _ predicate: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !predicate() {
        if ContinuousClock.now >= deadline { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
@Suite struct MacrosModelTests {
    // MARK: - Sync / caching

    @Test func refreshReplacesListAndPersistsCache() async {
        let sink = FakeMacrosSink()
        let macro = makeMacro(name: "Mission Control")
        sink.macroListResult = .success([macro])
        let store = makeStore()
        let model = MacrosModel(sink: sink, documentStore: store, haptics: makeHaptics())

        await waitUntil { model.macros.map(\.name) == ["Mission Control"] }
        #expect(model.macros.map(\.name) == ["Mission Control"])

        let cached = await store.load(.macroCache)
        #expect(cached.macros == [macro])
    }

    @Test func coldStartRendersCachedListBeforeAnyRefreshSucceeds() async {
        let store = makeStore()
        let cachedMacro = makeMacro(name: "Cached Macro")
        try? await store.save(MacroDocument(revision: 1, macros: [cachedMacro]), descriptor: .macroCache)

        let offlineSink = FakeMacrosSink()
        offlineSink.macroListResult = .failure(StubError())
        let model = MacrosModel(sink: offlineSink, documentStore: store, haptics: makeHaptics())

        // The cache load always wins the race against a failing refresh (nothing overwrites it).
        await waitUntil { model.macros.map(\.name) == ["Cached Macro"] }
        #expect(model.macros.map(\.name) == ["Cached Macro"])
    }

    @Test func macroCountReflectsSyncedList() async {
        let sink = FakeMacrosSink()
        sink.macroListResult = .success([makeMacro(name: "A"), makeMacro(name: "B")])
        let model = MacrosModel(sink: sink, documentStore: makeStore(), haptics: makeHaptics())

        await waitUntil { model.macroCount == 2 }
        #expect(model.macroCount == 2)
    }

    // MARK: - Confirmation gating (spec §5.5.5)

    @Test func nonConfirmingMacroInvokesImmediately() async {
        let sink = FakeMacrosSink()
        let model = MacrosModel(sink: sink, documentStore: makeStore(), haptics: makeHaptics())
        let macro = makeMacro(requiresConfirmation: false)

        model.tap(macro)
        await waitUntil { !sink.invokeMacroCalls.isEmpty }

        #expect(sink.invokeMacroCalls == [MacroInvokeCall(id: macro.id, confirmed: false)])
        #expect(model.pendingConfirmation == nil)
    }

    @Test func scriptKindAlwaysRequiresConfirmationBeforeSendingConfirmedTrue() async {
        let sink = FakeMacrosSink()
        let model = MacrosModel(sink: sink, documentStore: makeStore(), haptics: makeHaptics())
        // `Macro.init` forces `requiresConfirmation = true` for script kinds regardless of the
        // caller's argument (spec §5.5.1) — construct without passing it to prove that.
        let scriptMacro = Macro(name: "Danger", icon: "star", action: .shellCommand(command: "rm -rf /"), page: 0, order: 0)
        #expect(scriptMacro.requiresConfirmation == true)

        model.tap(scriptMacro)

        #expect(model.pendingConfirmation?.macro.id == scriptMacro.id)
        #expect(sink.invokeMacroCalls.isEmpty) // not sent until confirmed

        model.confirmPendingInvoke()
        await waitUntil { !sink.invokeMacroCalls.isEmpty }

        #expect(sink.invokeMacroCalls == [MacroInvokeCall(id: scriptMacro.id, confirmed: true)])
        #expect(model.pendingConfirmation == nil)
    }

    @Test func cancellingConfirmationNeverInvokes() async {
        let sink = FakeMacrosSink()
        let model = MacrosModel(sink: sink, documentStore: makeStore(), haptics: makeHaptics())
        let scriptMacro = Macro(name: "Danger", icon: "star", action: .appleScript(source: "tell app \"Finder\" to quit"), page: 0, order: 0)

        model.tap(scriptMacro)
        #expect(model.pendingConfirmation != nil)
        model.cancelPendingConfirmation()

        #expect(model.pendingConfirmation == nil)
        #expect(sink.invokeMacroCalls.isEmpty)
    }

    @Test func scriptMacroDisabledWhenHostScriptsAreOffSkipsTheWireEntirely() async {
        let sink = FakeMacrosSink()
        sink.scriptsAllowedOnHost = false
        let model = MacrosModel(sink: sink, documentStore: makeStore(), haptics: makeHaptics())
        let scriptMacro = Macro(name: "Danger", icon: "star", action: .appleScript(source: "beep"), page: 0, order: 0)

        model.tap(scriptMacro)

        #expect(model.currentError?.presentation.id == "E-MACRO-BLOCKED")
        #expect(model.pendingConfirmation == nil)
        #expect(sink.invokeMacroCalls.isEmpty)
    }

    // MARK: - Error mapping to spec §9 copy

    @Test func blockedByPolicyMapsToExactCopy() async throws {
        let sink = FakeMacrosSink()
        sink.invokeMacroOutcome = MacroInvokeOutcome(code: .blockedByPolicy)
        let model = MacrosModel(sink: sink, documentStore: makeStore(), haptics: makeHaptics())
        let macro = makeMacro()

        model.tap(macro)
        await waitUntil { model.currentError != nil }

        let presentation = try #require(model.currentError?.presentation)
        #expect(presentation.id == "E-MACRO-BLOCKED")
        #expect(presentation.title == "Blocked by Mac policy")
    }

    @Test func failedMapsToExactCopyWithNameAndMessage() async throws {
        let sink = FakeMacrosSink()
        sink.invokeMacroOutcome = MacroInvokeOutcome(code: .failed, message: "permission denied")
        let model = MacrosModel(sink: sink, documentStore: makeStore(), haptics: makeHaptics())
        let macro = makeMacro(name: "Do Not Disturb")

        model.tap(macro)
        await waitUntil { model.currentError != nil }

        let presentation = try #require(model.currentError?.presentation)
        #expect(presentation.id == "E-MACRO-FAILED")
        #expect(presentation.title == "Do Not Disturb failed: permission denied")
    }

    @Test func timeoutMapsToExactCopyWithName() async throws {
        let sink = FakeMacrosSink()
        sink.invokeMacroOutcome = MacroInvokeOutcome(code: .timeout)
        let model = MacrosModel(sink: sink, documentStore: makeStore(), haptics: makeHaptics())
        let macro = makeMacro(name: "Slow Script")

        model.tap(macro)
        await waitUntil { model.currentError != nil }

        let presentation = try #require(model.currentError?.presentation)
        #expect(presentation.id == "E-MACRO-TIMEOUT")
        #expect(presentation.title == "Slow Script timed out")
    }

    @Test func notFoundMapsToExactCopyAndRefreshesList() async throws {
        let sink = FakeMacrosSink()
        sink.invokeMacroOutcome = MacroInvokeOutcome(code: .notFound)
        let model = MacrosModel(sink: sink, documentStore: makeStore(), haptics: makeHaptics())
        let callsBefore = sink.requestMacroListCallCount
        let macro = makeMacro()

        model.tap(macro)
        await waitUntil { model.currentError != nil }

        let presentation = try #require(model.currentError?.presentation)
        #expect(presentation.id == "E-MACRO-NOTFOUND")
        #expect(presentation.title == "That macro was removed on the Mac")
        await waitUntil { sink.requestMacroListCallCount > callsBefore }
        #expect(sink.requestMacroListCallCount > callsBefore)
    }

    @Test func sinkThrowingMapsToGenericFallback() async {
        let sink = FakeMacrosSink()
        sink.invokeMacroError = StubError()
        let model = MacrosModel(sink: sink, documentStore: makeStore(), haptics: makeHaptics())
        let macro = makeMacro()

        model.tap(macro)
        await waitUntil { model.currentError != nil }

        #expect(model.currentError?.presentation.id == "E-GENERIC")
    }

    // MARK: - Large buttons preference persistence

    @Test func largeButtonsPreferencePersistsAcrossModelInstances() async {
        let store = makeStore()
        let sink = FakeMacrosSink()
        let model = MacrosModel(sink: sink, documentStore: store, haptics: makeHaptics())
        #expect(model.largeButtons == false)

        // `loadDisplayPreferences()` always completes before `refresh()` runs in `init`'s task
        // chain, so waiting for the first `requestMacroList()` call guarantees display-preference
        // hydration has already happened — only after that does setting `largeButtons` actually
        // persist rather than being silently overwritten by the in-flight initial load.
        await waitUntil { sink.requestMacroListCallCount > 0 }

        model.largeButtons = true
        // Give the async persistence Task a moment to land.
        try? await Task.sleep(for: .milliseconds(100))

        let reloaded = MacrosModel(sink: FakeMacrosSink(), documentStore: store, haptics: makeHaptics())
        await waitUntil { reloaded.largeButtons == true }
        #expect(reloaded.largeButtons == true)
    }
}
