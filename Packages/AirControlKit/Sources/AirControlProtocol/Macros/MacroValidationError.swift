import Foundation

/// Errors `MacroValidator` throws. Each case names the offending macro (by `name`, since `id`
/// alone is not user-legible) so a caller can build a useful diagnostic without re-deriving it.
public enum MacroValidationError: Error, LocalizedError, Sendable, Equatable {
    case nameEmpty(macro: String)
    case nameTooLong(macro: String, length: Int)
    case duplicateName(name: String)
    case invalidPage(macro: String, page: Int)
    case tooManyMacros(count: Int)
    case tooManyOnPage(page: Int, count: Int)
    case emptyKeyLabel(macro: String)
    case sequenceEmpty(macro: String)
    case sequenceTooLong(macro: String, count: Int)
    case sequenceStepTextTooLong(macro: String, length: Int)
    case sequenceDelayOutOfRange(macro: String, delayMs: Int)
    case bundleIDEmpty(macro: String)
    case urlTooLarge(macro: String, length: Int)
    case shortcutNameTooLong(macro: String, length: Int)
    case scriptTooLarge(macro: String, length: Int)
    case shellCommandTooLarge(macro: String, length: Int)

    public var errorDescription: String? {
        switch self {
        case .nameEmpty(let macro):
            "Macro '\(macro)' has an empty name."
        case .nameTooLong(let macro, let length):
            "Macro '\(macro)' name is \(length) characters, exceeding \(ProtocolConstants.macroNameMaxLength)."
        case .duplicateName(let name):
            "Two macros share the name '\(name)' (case-insensitive)."
        case .invalidPage(let macro, let page):
            "Macro '\(macro)' has page \(page), outside 0...\(ProtocolConstants.macroMaxPages - 1)."
        case .tooManyMacros(let count):
            "\(count) macros exceeds the limit of \(ProtocolConstants.macroMaxTotal)."
        case .tooManyOnPage(let page, let count):
            "Page \(page) has \(count) macros, exceeding \(ProtocolConstants.macroMaxPerPage)."
        case .emptyKeyLabel(let macro):
            "Macro '\(macro)' has an empty key combo label."
        case .sequenceEmpty(let macro):
            "Macro '\(macro)' has an empty key sequence."
        case .sequenceTooLong(let macro, let count):
            "Macro '\(macro)' sequence has \(count) steps, exceeding \(ProtocolConstants.macroSequenceMaxSteps)."
        case .sequenceStepTextTooLong(let macro, let length):
            "Macro '\(macro)' sequence text step is \(length) characters, exceeding \(ProtocolConstants.macroSequenceStepTextMaxLength)."
        case .sequenceDelayOutOfRange(let macro, let delayMs):
            "Macro '\(macro)' inter-step delay \(delayMs) ms is outside \(ProtocolConstants.macroSequenceInterStepDelayRangeMs)."
        case .bundleIDEmpty(let macro):
            "Macro '\(macro)' has an empty bundle ID."
        case .urlTooLarge(let macro, let length):
            "Macro '\(macro)' URL is \(length) bytes, exceeding \(ProtocolConstants.macroURLMaxBytes)."
        case .shortcutNameTooLong(let macro, let length):
            "Macro '\(macro)' shortcut name is \(length) characters, exceeding \(ProtocolConstants.macroShortcutNameMaxLength)."
        case .scriptTooLarge(let macro, let length):
            "Macro '\(macro)' AppleScript source is \(length) bytes, exceeding \(ProtocolConstants.macroScriptMaxBytes)."
        case .shellCommandTooLarge(let macro, let length):
            "Macro '\(macro)' shell command is \(length) bytes, exceeding \(ProtocolConstants.macroShellCommandMaxBytes)."
        }
    }
}
