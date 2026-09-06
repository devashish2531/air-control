// spec §5.5.4 "Execution" + §5.5.5 "Script gating and confirmation protocol" + §7.2 + §7.6 ("Script
// processes: 1 concurrent, 30–60 s timeout") + arch §4.4(d) sequence diagram. This actor is the `ME`
// node in that diagram: it never touches the network frame itself (no `i`/`ref`, no `SessionManager`
// type) — `SessionManager` (owned by the networking agent) is expected to call `invoke(...)`, then copy
// the triggering frame's message id into the returned `MacroResult.ref` before sending it over the wire.
import AirControlProtocol
import Foundation

/// One host's macro invocation engine (arch §3.3 `MacroEngine (actor)` row). Holds no network or
/// TrustStore state itself — the three gating facts (§5.5.5: global toggle, per-device flag, `confirmed`)
/// are passed in by the caller, which is exactly what the architecture doc's sequence diagram (§4.4(d))
/// shows `SessionManager` doing after asking `TrustStore` and reading the Preferences toggle.
public actor MacroEngine {
    private let store: any MacroStoreProviding
    private let executor: any MacroActionExecuting

    /// spec §7.6 "Script processes: 1 concurrent" / §5.5.4 "At most one script/shortcut process runs at
    /// a time per host (others get `macroResult{code: failed, message: "Another script is running"}")".
    /// Only `runShortcut`/`appleScript`/`shellCommand` take this lock — `keyCombo`, `keySequence`,
    /// `launchApp`, and `openURL` never contend for it.
    private var isProcessRunning = false

    public init(store: any MacroStoreProviding, executor: any MacroActionExecuting) {
        self.store = store
        self.executor = executor
    }

    /// spec §5.5.5's three-way gate, then §5.5.4's per-kind execution. `deviceAllowsScripts` is the
    /// invoking device's `TrustedDeviceRecord.allowScripts` (§5.6); `globalScriptsEnabled` is
    /// `HostSettings.allowScriptsGlobal` (Preferences › Security). Neither is read from a store directly
    /// here — see the type doc.
    public func invoke(
        _ invoke: MacroInvoke,
        from deviceID: String,
        deviceAllowsScripts: Bool,
        globalScriptsEnabled: Bool
    ) async -> MacroResult {
        guard let macro = await store.macro(id: invoke.id) else {
            return result(for: invoke, ok: false, message: "That macro was removed on the Mac", code: .notFound)
        }

        // spec §5.5.5, in order: (1) global toggle, (2) per-device flag, (3) `confirmed`. Only script
        // kinds (`Macro.isScript` — appleScript/shellCommand) are subject to (1) and (2); `runShortcut`
        // is a subprocess too but is not gated by the script policy (spec places it outside "script
        // kind" — §5.5.1's `isScript` covers only appleScript/shellCommand — though it still shares the
        // one-concurrent-process lock below since it is still a `Process` launch).
        if macro.isScript {
            guard globalScriptsEnabled else {
                return result(for: invoke, ok: false, message: "Blocked by Mac policy", code: .blockedByPolicy)
            }
            guard deviceAllowsScripts else {
                return result(for: invoke, ok: false, message: "Blocked by Mac policy", code: .blockedByPolicy)
            }
        }

        // spec §5.5.5: "The client shows the confirmation alert for any macro with `requiresConfirmation`
        // ... before sending `confirmed: true`" — enforced host-side for every kind (not just scripts),
        // since the host is the only party that can't be spoofed into skipping it.
        if macro.requiresConfirmation, !invoke.confirmed {
            return result(for: invoke, ok: false, message: "Confirmation required", code: .confirmationRequired)
        }

        if macro.action.isProcessBased {
            guard !isProcessRunning else {
                return result(for: invoke, ok: false, message: "Another script is running", code: .failed)
            }
            isProcessRunning = true
            defer { isProcessRunning = false }
            return await execute(macro: macro, invoke: invoke)
        }

        return await execute(macro: macro, invoke: invoke)
    }

    private func execute(macro: Macro, invoke: MacroInvoke) async -> MacroResult {
        let outcome = await executor.execute(macro.action)
        let code: MacroResultCode = outcome.timedOut ? .timeout : (outcome.ok ? .ok : .failed)
        // spec §5.5.4: "Results → `macroResult` with `message` = first 120 chars of stdout or stderr."
        let message = String(outcome.message.prefix(120))
        return result(for: invoke, ok: outcome.ok, message: message, code: code)
    }

    private func result(for invoke: MacroInvoke, ok: Bool, message: String, code: MacroResultCode) -> MacroResult {
        // `ref` (the triggering frame's envelope message id) is not visible at this layer — see the type
        // doc. `0` is a placeholder the caller is expected to overwrite before sending.
        MacroResult(ref: 0, id: invoke.id, ok: ok, message: message, code: code)
    }
}

private extension MacroAction {
    /// The subset of kinds that launch a subprocess and therefore contend for the one-concurrent-process
    /// lock (spec §7.6): `runShortcut`, `appleScript`, `shellCommand`. Deliberately broader than
    /// `isScript` (which only covers the two kinds forced to `requiresConfirmation = true`).
    var isProcessBased: Bool {
        switch self {
        case .runShortcut, .appleScript, .shellCommand:
            true
        case .keyCombo, .keySequence, .launchApp, .openURL:
            false
        }
    }
}
