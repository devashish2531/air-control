// Wiring seam for the integration agent — CLAUDE.md / assignment: "provide `MacroFeature.make
// (environment:)` / clear init signatures ... so the integration agent can swap `PlaceholderMacroStore`."
// Deliberately does not touch `AppEnvironment.swift` (not owned by this module) — the integration agent
// is expected to call `MacroFeature.make`, then assign the result's `store` to
// `AppEnvironment.macroStore` and hold `engine`/`store` wherever `SessionManager`'s `macroInvoke` and
// `hello.macroRevision` handling lives.
import Foundation

/// Everything the macro subsystem needs, already wired together.
public struct MacroFeature: Sendable {
    public let store: MacroStore
    public let engine: MacroEngine

    public init(store: MacroStore, engine: MacroEngine) {
        self.store = store
        self.engine = engine
    }

    /// Builds a `MacroStore` backed by `environment.documentStore` (so it shares the same
    /// `~/Library/Application Support/AirMouseHelper/` base directory as every other document, arch
    /// §6.3) and a `MacroEngine` around it, loads/seeds `Macros.json`, and returns both.
    ///
    /// - Parameter keyEmitter: the injection agent's `EventInjector` once it conforms to
    ///   `KeyEventEmitting`; defaults to `NullKeyEventEmitter()` so this compiles and runs (as a no-op
    ///   for `keyCombo`/`keySequence`) before that wiring lands.
    @MainActor
    public static func make(
        environment: AppEnvironment,
        keyEmitter: any KeyEventEmitting = NullKeyEventEmitter()
    ) async -> MacroFeature {
        let store = MacroStore(documentStore: environment.documentStore)
        // Touch the store once so `Macros.json` is loaded/seeded before the editor or any `macroInvoke`
        // arrives, rather than lazily on first access mid-request.
        _ = await store.macroCount
        let executor = DefaultMacroActionExecutor(keyEmitter: keyEmitter)
        let engine = MacroEngine(store: store, executor: executor)
        return MacroFeature(store: store, engine: engine)
    }
}
