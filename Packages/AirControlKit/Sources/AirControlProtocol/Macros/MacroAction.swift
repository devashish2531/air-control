import Foundation

/// What a `Macro` does when invoked. spec §5.5.1:
/// ```swift
/// public enum MacroAction: Codable, Hashable {
///   case keyCombo(modifiers: Set<Modifier>, keyCode: UInt16, keyLabel: String)
///   case keySequence(steps: [SequenceStep] /*≤16*/, interStepDelayMs: Int /*0–2000*/)
///   case launchApp(bundleID: String, activateIfRunning: Bool)
///   case openURL(url: URL /*http, https, file, or registered scheme; ≤ 2 KB*/)
///   case runShortcut(name: String /*≤ 100*/)
///   case appleScript(source: String /*≤ 8 KB*/)
///   case shellCommand(command: String /*≤ 2 KB*/)
/// }
/// ```
/// Deviation: `modifiers` is `KeyModifiers` (this package's canonical modifier `OptionSet`,
/// `Keycodes/KeyModifiers.swift`) rather than a bespoke `Set<Modifier>` — there is no separate
/// `Modifier` type in this package, and reusing `KeyModifiers` keeps every modifier-bearing field
/// (`click.modifiers`, `key.modifiers`, `modifiers.flags`, and this one) on the same type.
///
/// Execution (spec §5.5.4 — `EventInjector`, `NSWorkspace`, `/usr/bin/shortcuts`, `osascript`,
/// `/bin/zsh`) lives entirely on the host side, outside this module; this is only the wire/storage
/// shape. `Codable`/`Hashable` are compiler-synthesized (see `SequenceStep`'s doc comment for the
/// resulting JSON shape).
public enum MacroAction: Codable, Hashable, Sendable, Equatable {
    case keyCombo(modifiers: KeyModifiers, keyCode: UInt16, keyLabel: String)
    case keySequence(steps: [SequenceStep], interStepDelayMs: Int)
    case launchApp(bundleID: String, activateIfRunning: Bool)
    case openURL(url: URL)
    case runShortcut(name: String)
    case appleScript(source: String)
    case shellCommand(command: String)

    /// spec §5.5.1: "`isScript` computed property" — forces `requiresConfirmation` on `Macro`
    /// construction (§5.5.1) and gates execution behind the script policy checks of §5.5.5.
    public var isScript: Bool {
        switch self {
        case .appleScript, .shellCommand:
            true
        default:
            false
        }
    }
}
