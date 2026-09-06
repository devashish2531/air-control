// UI-only editable form of `Macro`/`MacroAction` (spec §5.5.1, §5.5.3 Editor UI). `MacroAction` is an
// enum with associated values, which SwiftUI `Form` controls can't bind to directly one field at a
// time — `MacroDraft` is a flat, `Equatable` struct holding every kind's fields simultaneously (unused
// ones for the current `kind` are simply not shown), converted to/from a real `Macro` only at the
// store-call boundary (`makeMacro()`), never itself persisted or sent anywhere.
import AirControlProtocol
import Foundation

struct MacroDraft: Identifiable, Equatable {
    enum ActionKind: String, CaseIterable, Identifiable {
        case keyCombo, keySequence, launchApp, openURL, runShortcut, appleScript, shellCommand
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .keyCombo: "Key Combo"
            case .keySequence: "Key Sequence"
            case .launchApp: "Launch App"
            case .openURL: "Open URL"
            case .runShortcut: "Run Shortcut"
            case .appleScript: "AppleScript"
            case .shellCommand: "Shell Command"
            }
        }

        /// spec §5.5.1: "`requiresConfirmation` forced `true` for `appleScript`/`shellCommand`" —
        /// mirrors `MacroAction.isScript` for the two kinds the draft can represent before it becomes a
        /// real `MacroAction`.
        var isScript: Bool { self == .appleScript || self == .shellCommand }
    }

    var id: UUID
    var name: String
    var icon: String
    var tint: MacroTint?
    var page: Int
    var order: Int
    var showOnMediaPage: Bool
    var requiresConfirmationOverride: Bool
    var createdAt: Date

    var kind: ActionKind

    // keyCombo
    var comboModifiers: KeyModifiers = []
    var comboKeyCode: UInt16?
    var comboKeyLabel: String = ""

    // keySequence
    var sequenceSteps: [SequenceStep] = []
    var sequenceDelayMs: Int = 100

    // launchApp
    var bundleID: String = ""
    var activateIfRunning: Bool = true

    // openURL
    var urlString: String = ""

    // runShortcut
    var shortcutName: String = ""

    // appleScript / shellCommand
    var scriptSource: String = ""

    /// spec §5.5.1: forced `true` for script kinds regardless of the user-facing checkbox.
    var requiresConfirmation: Bool { kind.isScript ? true : requiresConfirmationOverride }

    static func new(page: Int, order: Int) -> MacroDraft {
        MacroDraft(
            id: UUID(),
            name: "",
            icon: "command",
            tint: nil,
            page: page,
            order: order,
            showOnMediaPage: false,
            requiresConfirmationOverride: false,
            createdAt: Date(),
            kind: .keyCombo
        )
    }

    init(
        id: UUID,
        name: String,
        icon: String,
        tint: MacroTint?,
        page: Int,
        order: Int,
        showOnMediaPage: Bool,
        requiresConfirmationOverride: Bool,
        createdAt: Date,
        kind: ActionKind
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.tint = tint
        self.page = page
        self.order = order
        self.showOnMediaPage = showOnMediaPage
        self.requiresConfirmationOverride = requiresConfirmationOverride
        self.createdAt = createdAt
        self.kind = kind
    }

    init(macro: Macro) {
        self.init(
            id: macro.id,
            name: macro.name,
            icon: macro.icon,
            tint: macro.tint,
            page: macro.page,
            order: macro.order,
            showOnMediaPage: macro.showOnMediaPage,
            requiresConfirmationOverride: macro.requiresConfirmation,
            createdAt: macro.createdAt,
            kind: .keyCombo // overwritten immediately below
        )
        switch macro.action {
        case .keyCombo(let modifiers, let keyCode, let keyLabel):
            kind = .keyCombo
            comboModifiers = modifiers
            comboKeyCode = keyCode
            comboKeyLabel = keyLabel
        case .keySequence(let steps, let interStepDelayMs):
            kind = .keySequence
            sequenceSteps = steps
            sequenceDelayMs = interStepDelayMs
        case .launchApp(let bundleID, let activateIfRunning):
            kind = .launchApp
            self.bundleID = bundleID
            self.activateIfRunning = activateIfRunning
        case .openURL(let url):
            kind = .openURL
            urlString = url.absoluteString
        case .runShortcut(let name):
            kind = .runShortcut
            shortcutName = name
        case .appleScript(let source):
            kind = .appleScript
            scriptSource = source
        case .shellCommand(let command):
            kind = .shellCommand
            scriptSource = command
        }
    }

    /// Builds the `MacroAction` for the current `kind`, or `nil` if the kind-specific fields aren't
    /// filled in enough to construct one yet (e.g. no key recorded, no app chosen). Field-*limit*
    /// validation (lengths, byte caps, sequence step count, ...) is left to `MacroValidator`, run by the
    /// store on `create`/`update` — this only guards against building a nonsensical action at all.
    func makeAction() -> MacroAction? {
        switch kind {
        case .keyCombo:
            guard let comboKeyCode, !comboKeyLabel.isEmpty else { return nil }
            return .keyCombo(modifiers: comboModifiers, keyCode: comboKeyCode, keyLabel: comboKeyLabel)
        case .keySequence:
            guard !sequenceSteps.isEmpty else { return nil }
            return .keySequence(steps: sequenceSteps, interStepDelayMs: sequenceDelayMs)
        case .launchApp:
            guard !bundleID.isEmpty else { return nil }
            return .launchApp(bundleID: bundleID, activateIfRunning: activateIfRunning)
        case .openURL:
            guard let url = URL(string: urlString), url.scheme != nil else { return nil }
            return .openURL(url: url)
        case .runShortcut:
            guard !shortcutName.isEmpty else { return nil }
            return .runShortcut(name: shortcutName)
        case .appleScript:
            guard !scriptSource.isEmpty else { return nil }
            return .appleScript(source: scriptSource)
        case .shellCommand:
            guard !scriptSource.isEmpty else { return nil }
            return .shellCommand(command: scriptSource)
        }
    }

    func makeMacro() -> Macro? {
        guard let action = makeAction() else { return nil }
        return Macro(
            id: id,
            name: name,
            icon: icon,
            tint: tint,
            action: action,
            page: page,
            order: order,
            showOnMediaPage: showOnMediaPage,
            requiresConfirmation: requiresConfirmationOverride,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
}
