// Features/Macros/MacrosModel.swift
// Macros tab state per spec §4.1.8 and §5.5 (macro engine sync + confirmation protocol). Syncs a
// `[Macro]` list from the Mac through `RemoteCommandSink`, caches it via the shell's
// `DocumentStore` so a cold launch renders instantly (spec FR-MC-009 / AM-MC "cached set renders
// instantly on reconnect"), and gates script-kind invocation behind the confirmation sheet per
// spec §5.5.5.

import Foundation
import Observation
import AirControlProtocol

/// Per-phone display preference (AM-MC-07: "a 'large buttons' layout for macros (2 columns
/// instead of 4) selectable on the phone"). Not part of the wire's `MacroDocument` — this is
/// purely a client-side rendering choice, so it gets its own tiny cached document rather than
/// living on `Macro` itself.
struct MacrosDisplayPreferences: Codable, Sendable, Equatable {
    var largeButtons: Bool
    init(largeButtons: Bool = false) { self.largeButtons = largeButtons }
}

extension DocumentDescriptor where T == MacroDocument {
    /// The client's macro cache (spec §5.5.6 "the client replaces its cache wholesale"; arch §6.3
    /// gives `"Macros/\(hostID).json"` as the illustrative path — this agent has no `hostID`
    /// plumbed through `RemoteCommandSink`, only `ConnectionManaging.currentHostName`, which is
    /// display text, not a stable identifier, so the cache is a single shared file rather than
    /// per-host. See this agent's final-report deviation note.
    static let macroCache = DocumentDescriptor<MacroDocument>(
        relativePath: "Macros/Cache.json",
        schemaName: MacroDocument.schemaName,
        currentVersion: 1,
        defaultValue: { MacroDocument(revision: 0, macros: []) }
    )
}

extension DocumentDescriptor where T == MacrosDisplayPreferences {
    static let macrosDisplay = DocumentDescriptor<MacrosDisplayPreferences>(
        relativePath: "Macros/DisplayPreferences.json",
        schemaName: "macros-display",
        currentVersion: 1,
        defaultValue: { MacrosDisplayPreferences() }
    )
}

/// A transient success toast (spec §4.1.8: "`macroResult` → toast (success/failure, message)").
/// Failure toasts reuse `AppError`/`ErrorPresentation` (Support/ErrorPresentation.swift) so their
/// copy matches spec §9 exactly; there is no §9 row for the success case, so this carries this
/// agent's own (non-spec-mandated) copy — see final-report deviation note.
public struct MacroToast: Sendable, Equatable, Identifiable {
    public let id = UUID()
    public let message: String
}

/// The confirmation sheet's content (spec §4.1.8 "`requiresConfirmation` → alert 'Run <name>?'
/// first"; spec §5.5.5 describes the protocol this satisfies client-side: the sheet must be shown
/// before `confirmed: true` is ever sent for a macro with `requiresConfirmation`, unconditionally
/// true for script kinds).
public struct MacroConfirmationRequest: Sendable, Equatable, Identifiable {
    public var id: UUID { macro.id }
    public let macro: Macro

    /// Human-readable action-kind label shown in the sheet ("shows the macro name, kind, and
    /// warning" per this agent's assignment).
    public var kindDescription: String {
        switch macro.action {
        case .keyCombo: String(localized: "Key combo", comment: "Macro kind label")
        case .keySequence: String(localized: "Key sequence", comment: "Macro kind label")
        case .launchApp: String(localized: "Launch app", comment: "Macro kind label")
        case .openURL: String(localized: "Open URL", comment: "Macro kind label")
        case .runShortcut: String(localized: "Run Shortcut", comment: "Macro kind label")
        case .appleScript: String(localized: "AppleScript", comment: "Macro kind label")
        case .shellCommand: String(localized: "Shell command", comment: "Macro kind label")
        }
    }

    /// Warning copy. Script kinds get the stronger "runs code on your Mac" warning (spec §5.5.5's
    /// entire premise); other `requiresConfirmation` macros (a Mac author can set this flag on any
    /// kind, spec §5.5.1) get a lighter "this will run on your Mac" notice.
    public var warning: String {
        if macro.isScript {
            String(localized: "This runs \(kindDescription.lowercased()) on your Mac. Only continue if you trust it.", comment: "Macro confirmation warning for script kinds")
        } else {
            String(localized: "This will run on your Mac.", comment: "Macro confirmation warning for non-script kinds")
        }
    }
}

/// `@Observable` macro store for the Macros tab. Conforms to `MacroStoreProviding`
/// (App/ServiceProtocols.swift) so `AppEnvironment.macros` can hold this instance once wired.
@MainActor
@Observable
public final class MacrosModel: MacroStoreProviding {
    public private(set) var macros: [Macro] = []
    public private(set) var isRefreshing = false
    public private(set) var invokingMacroIDs: Set<UUID> = []
    public var currentError: AppError?
    public var toast: MacroToast?
    public var pendingConfirmation: MacroConfirmationRequest?

    public var largeButtons: Bool = false {
        didSet {
            guard oldValue != largeButtons, hasLoadedDisplayPreferences else { return }
            Task { await self.persistDisplayPreferences() }
        }
    }

    /// `hostState.scriptsAllowed` mirrored through the sink (spec §11.1, §5.5.5). Script-kind
    /// macro buttons render disabled when this is `false` (AM-MC-05).
    public var scriptsAllowedOnHost: Bool { sink.scriptsAllowedOnHost }

    public var macroCount: Int { macros.count }

    /// 0-based pages actually in use (spec §4.1.8: "Pages 0–5"), always at least page 0 so an
    /// empty store still has one (empty) page to render the empty state into.
    public var pageIndices: [Int] {
        let highest = macros.map(\.page).max() ?? 0
        return Array(0...min(highest, ProtocolConstants.macroMaxPages - 1))
    }

    private let sink: any RemoteCommandSink
    private let documentStore: DocumentStore
    private let haptics: any HapticsService
    private var revisionCounter = 0
    private var hasLoadedDisplayPreferences = false

    public init(sink: any RemoteCommandSink, documentStore: DocumentStore, haptics: any HapticsService) {
        self.sink = sink
        self.documentStore = documentStore
        self.haptics = haptics
        Task { [weak self] in
            await self?.loadCachedMacros()
            await self?.loadDisplayPreferences()
            await self?.refresh()
        }
    }

    public func macros(onPage page: Int) -> [Macro] {
        macros.filter { $0.page == page }.sorted { $0.order < $1.order }
    }

    /// Pull-to-refresh and initial sync (spec §5.5.6 "the client replaces its cache wholesale").
    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let fetched = try await sink.requestMacroList()
            macros = fetched
            await persistCache(fetched)
        } catch {
            Log.app.error("MacrosModel refresh failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Entry point for a macro button tap (spec §4.1.8 "Tap → `macroInvoke`;
    /// `requiresConfirmation` → alert 'Run <name>?' first").
    public func tap(_ macro: Macro) {
        guard !invokingMacroIDs.contains(macro.id) else { return }
        if macro.isScript, !scriptsAllowedOnHost {
            // spec §5.5.5: the host would reject with `blockedByPolicy` anyway; disabling
            // proactively (AM-MC-05) still routes through the exact same §9 copy.
            currentError = .macroBlocked
            return
        }
        if macro.requiresConfirmation {
            pendingConfirmation = MacroConfirmationRequest(macro: macro)
            return
        }
        Task { await invoke(macro, confirmed: false) }
    }

    /// Called by the confirmation sheet's "Run" button — the only call site that ever passes
    /// `confirmed: true` (spec §5.5.5).
    public func confirmPendingInvoke() {
        guard let request = pendingConfirmation else { return }
        pendingConfirmation = nil
        Task { await invoke(request.macro, confirmed: true) }
    }

    public func cancelPendingConfirmation() {
        pendingConfirmation = nil
    }

    private func invoke(_ macro: Macro, confirmed: Bool) async {
        invokingMacroIDs.insert(macro.id)
        defer { invokingMacroIDs.remove(macro.id) }
        do {
            let outcome = try await sink.invokeMacro(id: macro.id, confirmed: confirmed)
            apply(outcome, for: macro)
        } catch {
            haptics.fire(.macroFailure)
            currentError = .generic(code: String(describing: error))
        }
    }

    private func apply(_ outcome: MacroInvokeOutcome, for macro: Macro) {
        switch outcome.code {
        case .ok:
            haptics.fire(.macroSuccess)
            toast = MacroToast(message: String(localized: "\(macro.name) ran", comment: "Macro invoke success toast"))
        case .blockedByPolicy:
            haptics.fire(.macroFailure)
            currentError = .macroBlocked
        case .failed:
            haptics.fire(.macroFailure)
            currentError = .macroFailed(name: macro.name, message: outcome.message)
        case .timeout:
            haptics.fire(.macroFailure)
            currentError = .macroTimeout(name: macro.name)
        case .notFound:
            haptics.fire(.macroFailure)
            currentError = .macroNotFound
            Task { await refresh() } // spec §9 E-MACRO-NOTFOUND: "(list refreshes)"
        case .confirmationRequired:
            // Should not happen — this model never sends `confirmed: false` for a macro with
            // `requiresConfirmation`. Falls back to the generic peer-error copy (spec §9's
            // closing rule) rather than silently dropping it.
            haptics.fire(.macroFailure)
            currentError = .generic(code: "confirmationRequired")
        }
    }

    // MARK: - Persistence

    private func loadCachedMacros() async {
        let document = await documentStore.load(.macroCache)
        macros = document.macros
        revisionCounter = document.revision
    }

    private func persistCache(_ macros: [Macro]) async {
        revisionCounter += 1
        let document = MacroDocument(revision: revisionCounter, macros: macros)
        do {
            try await documentStore.save(document, descriptor: .macroCache)
        } catch {
            Log.app.error("MacrosModel failed to persist macro cache: \(String(describing: error), privacy: .public)")
        }
    }

    private func loadDisplayPreferences() async {
        let prefs = await documentStore.load(.macrosDisplay)
        largeButtons = prefs.largeButtons
        hasLoadedDisplayPreferences = true
    }

    private func persistDisplayPreferences() async {
        do {
            try await documentStore.save(MacrosDisplayPreferences(largeButtons: largeButtons), descriptor: .macrosDisplay)
        } catch {
            Log.app.error("MacrosModel failed to persist display preferences: \(String(describing: error), privacy: .public)")
        }
    }
}
