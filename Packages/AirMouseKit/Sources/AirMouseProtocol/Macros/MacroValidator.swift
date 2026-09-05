import Foundation

/// Shared macro validation, run identically on both sides (spec §5.5.1: "Validation (shared, runs
/// on both sides)"). This module cannot check "`icon` must be a known SF Symbol on the validating
/// OS" (spec §5.5.1) — that requires SwiftUI/UIKit's symbol catalog, unavailable to a
/// Foundation-only package — so `validate(_:)` only checks that `icon` is non-empty; the apps are
/// responsible for the SF Symbol catalog check and for rendering an unknown icon as `command`
/// (the spec's documented fallback) rather than rejecting the macro.
public enum MacroValidator {
    /// Validates one macro's own field limits (name length, action-specific limits). Does not
    /// check cross-macro rules (uniqueness, per-page/total counts) — use `validate(all:)` for those.
    public static func validate(_ macro: Macro) throws {
        guard !macro.name.isEmpty else {
            throw MacroValidationError.nameEmpty(macro: macro.name)
        }
        guard macro.name.count <= ProtocolConstants.macroNameMaxLength else {
            throw MacroValidationError.nameTooLong(macro: macro.name, length: macro.name.count)
        }
        guard (0..<ProtocolConstants.macroMaxPages).contains(macro.page) else {
            throw MacroValidationError.invalidPage(macro: macro.name, page: macro.page)
        }

        switch macro.action {
        case .keyCombo(_, _, let keyLabel):
            guard !keyLabel.isEmpty else {
                throw MacroValidationError.emptyKeyLabel(macro: macro.name)
            }

        case .keySequence(let steps, let interStepDelayMs):
            guard !steps.isEmpty else {
                throw MacroValidationError.sequenceEmpty(macro: macro.name)
            }
            guard steps.count <= ProtocolConstants.macroSequenceMaxSteps else {
                throw MacroValidationError.sequenceTooLong(macro: macro.name, count: steps.count)
            }
            guard ProtocolConstants.macroSequenceInterStepDelayRangeMs.contains(interStepDelayMs) else {
                throw MacroValidationError.sequenceDelayOutOfRange(macro: macro.name, delayMs: interStepDelayMs)
            }
            for step in steps {
                if case .text(let text) = step, text.count > ProtocolConstants.macroSequenceStepTextMaxLength {
                    throw MacroValidationError.sequenceStepTextTooLong(macro: macro.name, length: text.count)
                }
            }

        case .launchApp(let bundleID, _):
            guard !bundleID.isEmpty else {
                throw MacroValidationError.bundleIDEmpty(macro: macro.name)
            }

        case .openURL(let url):
            let length = url.absoluteString.utf8.count
            guard length <= ProtocolConstants.macroURLMaxBytes else {
                throw MacroValidationError.urlTooLarge(macro: macro.name, length: length)
            }

        case .runShortcut(let name):
            guard name.count <= ProtocolConstants.macroShortcutNameMaxLength else {
                throw MacroValidationError.shortcutNameTooLong(macro: macro.name, length: name.count)
            }

        case .appleScript(let source):
            let length = source.utf8.count
            guard length <= ProtocolConstants.macroScriptMaxBytes else {
                throw MacroValidationError.scriptTooLarge(macro: macro.name, length: length)
            }

        case .shellCommand(let command):
            let length = command.utf8.count
            guard length <= ProtocolConstants.macroShellCommandMaxBytes else {
                throw MacroValidationError.shellCommandTooLarge(macro: macro.name, length: length)
            }
        }
    }

    /// Validates an entire macro list: every macro individually (`validate(_:)`), plus the
    /// cross-macro rules of spec §5.5.1: "limits above; 64 macros; ≤ 12 per page; unique names
    /// (case-insensitive)".
    public static func validate(all macros: [Macro]) throws {
        guard macros.count <= ProtocolConstants.macroMaxTotal else {
            throw MacroValidationError.tooManyMacros(count: macros.count)
        }

        var seenNames = Set<String>()
        for macro in macros {
            try validate(macro)
            let key = macro.name.lowercased()
            guard seenNames.insert(key).inserted else {
                throw MacroValidationError.duplicateName(name: macro.name)
            }
        }

        let byPage = Dictionary(grouping: macros, by: \.page)
        for (page, pageMacros) in byPage where pageMacros.count > ProtocolConstants.macroMaxPerPage {
            throw MacroValidationError.tooManyOnPage(page: page, count: pageMacros.count)
        }
    }
}
