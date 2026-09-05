// Features/Remote/RemoteCommandSink.swift
// Output boundary for the Remote and Macros features (spec §4.1.7 Remote, §4.1.8 Macros, §5.5
// macro engine). This module owns no networking (CLAUDE.md: "Only `airmouse-cli` and the two apps
// import Network.framework" — and even within the app, this feature never imports Network
// directly); everything a button press needs to become a wire message goes through this single
// protocol, which the Connection agent's concrete type (or an adapter over it) conforms to.
//
// Per this agent's assignment: "Do NOT import Network or touch ConnectionManager,
// ServiceProtocols.swift, or AppEnvironment.swift." `frontmostAppName` and `scriptsAllowedOnHost`
// mirror two fields of the wire's `hostState` (spec §11.1: `frontmostApp`, `scriptsAllowed`) that
// this module needs (presenter header profile detection §4.1.7; script-macro gating §5.5.5) but
// that `ConnectionManaging` (App/ServiceProtocols.swift) does not expose — rather than widen that
// shared protocol (out of bounds for this agent) or touch AppEnvironment, they are folded into
// this sink, which the integration agent can satisfy from the same `hostState` stream its
// `ConnectionManager` already parses.
//
// `MacroInvoke.id`/`Macro.id` are `UUID` on the wire model (AirMouseProtocol/Macros/*), so
// `invokeMacro(id:confirmed:)` takes `UUID`, not `String` — a deliberate deviation from this
// assignment's illustrative snippet ("adjust names sensibly").

import Foundation
import AirMouseProtocol

/// A macro invocation's resolved outcome, once the host's `macroResult` (H→C, spec §3.4.5/§5.5.4)
/// arrives for the matching `ref`. Reuses `MacroResultCode` (AirMouseProtocol/Macros) — a `Macro`
/// invocation is not `.ok`/failure alone; the exact `code` drives which spec §9 toast copy the
/// Macros feature shows (E-MACRO-BLOCKED/-FAILED/-TIMEOUT/-NOTFOUND).
public struct MacroInvokeOutcome: Sendable, Equatable {
    public var code: MacroResultCode
    /// First ≤ 120 chars of stdout/stderr for script/shortcut kinds (spec §5.5.4); empty for
    /// non-script kinds and for `.ok`.
    public var message: String

    public init(code: MacroResultCode, message: String = "") {
        self.code = code
        self.message = message
    }
}

/// Everything a Remote/Macros button needs to become a wire effect. Concrete conformance is the
/// Connection agent's job (or a thin adapter over its richer session type); this module only
/// depends on this protocol.
@MainActor
public protocol RemoteCommandSink: AnyObject {
    /// Presenter/media buttons that map onto the wire's `mediaKey` message (`key`, `action`,
    /// spec §11.1). Fire-and-forget — sent as `action: .tap` for buttons that behave like a single
    /// keystroke; long-press-to-repeat controls (volume, brightness) call this repeatedly on a
    /// timer rather than sending `.down`/`.up`, since the host's media-key posting is inherently
    /// discrete per spec §5.3.7 (no separate "held" state to model beyond re-tapping).
    func sendMediaKey(_ key: MediaKey)

    /// Presenter navigation (arrow keys), Blank/Start/Exit shortcuts, and Lock Screen — maps onto
    /// the wire's `key` message (`code`, `modifiers`, spec §11.1) with a `tap` (down+up) action.
    /// `virtualKey` is one of the `VirtualKey.kVK_*` constants (AirMouseProtocol/Keycodes).
    func sendShortcut(virtualKey: UInt16, modifiers: KeyModifiers)

    /// Invokes a synced macro by id (wire `macroInvoke`, spec §5.5.5). `confirmed` must be `true`
    /// only after the caller has shown the confirmation alert for any macro with
    /// `requiresConfirmation` set (always true for `.appleScript`/`.shellCommand`, spec §5.5.1) —
    /// this method does not itself gate on that; `MacrosModel`/`RemoteModel` are responsible for
    /// having shown the sheet first. Suspends until the matching `macroResult` (by `ref`) arrives,
    /// or throws if the sink cannot reach the host at all (distinct from a *received* failure,
    /// which comes back as a non-`.ok` `MacroInvokeOutcome`, not a thrown error).
    func invokeMacro(id: UUID, confirmed: Bool) async throws -> MacroInvokeOutcome

    /// Fetches the current synced macro list (wire `macroList`, spec §5.5.6). Used for pull-to-
    /// refresh and initial load; `MacrosModel` layers its own on-disk cache underneath so a cold
    /// launch renders instantly before this resolves (spec FR-MC-009).
    func requestMacroList() async throws -> [Macro]

    /// Best-effort frontmost Mac app name, mirroring `hostState.frontmostApp` (spec §11.1) — drives
    /// the Remote presenter header's app name and Keynote/PowerPoint/Generic profile detection
    /// (spec §4.1.7). `nil` when unknown (not connected, or the host hasn't reported one yet).
    var frontmostAppName: String? { get }

    /// Mirrors `hostState.scriptsAllowed` (spec §11.1) — both script-gating checks of spec §5.5.5
    /// ((1) Mac-wide "Allow script macros", (2) this device's "Allow scripts") collapse to this one
    /// wire field from the client's point of view. Drives the Macros grid's disabled state for
    /// script-kind macros (AM-MC-05) without a round trip: the host would reject with
    /// `blockedByPolicy` anyway (spec §9 E-MACRO-BLOCKED), but disabling proactively avoids the
    /// wait. `true` when unknown (not connected) so the grid does not falsely show scripts as
    /// blocked before the first `hostState` arrives — the host still enforces the real policy.
    var scriptsAllowedOnHost: Bool { get }
}

/// Default stand-in so `RemoteScreen()`/`MacrosScreen()` (RootTabView's current zero-argument call
/// sites) keep compiling before the integration agent wires a real sink through
/// `RemoteFeature.make(environment:sink:)` / `MacrosFeature.make(environment:sink:)`. Mirrors
/// `NoOp*` naming in App/DefaultServices.swift (owned by another agent; not touched here — this is
/// this feature's own no-op, in its own directory).
@MainActor
public final class NoOpRemoteCommandSink: RemoteCommandSink {
    public var frontmostAppName: String?
    public var scriptsAllowedOnHost: Bool = true

    public init(frontmostAppName: String? = nil, scriptsAllowedOnHost: Bool = true) {
        self.frontmostAppName = frontmostAppName
        self.scriptsAllowedOnHost = scriptsAllowedOnHost
    }

    public func sendMediaKey(_ key: MediaKey) {
        Log.app.notice("NoOpRemoteCommandSink.sendMediaKey(\(key.wireName, privacy: .public)) — no Connection agent wired yet")
    }

    public func sendShortcut(virtualKey: UInt16, modifiers: KeyModifiers) {
        Log.app.notice("NoOpRemoteCommandSink.sendShortcut(virtualKey: \(virtualKey)) — no Connection agent wired yet")
    }

    public func invokeMacro(id: UUID, confirmed: Bool) async throws -> MacroInvokeOutcome {
        Log.app.notice("NoOpRemoteCommandSink.invokeMacro — no Connection agent wired yet")
        return MacroInvokeOutcome(code: .notFound, message: "")
    }

    public func requestMacroList() async throws -> [Macro] {
        []
    }
}
