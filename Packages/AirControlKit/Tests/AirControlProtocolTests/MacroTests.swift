import Foundation
import Testing
@testable import AirControlProtocol

@Suite struct MacroTests {
    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func macro(named name: String, action: MacroAction, page: Int = 0, order: Int = 0) -> Macro {
        Macro(
            id: UUID(),
            name: name,
            icon: "star.fill",
            tint: .blue,
            action: action,
            page: page,
            order: order,
            showOnMediaPage: false,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
    }

    static let sampleActions: [MacroAction] = [
        .keyCombo(modifiers: [.command, .shift], keyCode: 20, keyLabel: "⌘⇧4"),
        .keySequence(steps: [.combo(modifiers: [.command], keyCode: 8, keyLabel: "⌘C"), .text("hello")], interStepDelayMs: 50),
        .launchApp(bundleID: "com.apple.Safari", activateIfRunning: true),
        .openURL(url: URL(string: "https://example.com")!),
        .runShortcut(name: "My Shortcut"),
        .appleScript(source: "tell application \"Finder\" to activate"),
        .shellCommand(command: "echo hello"),
    ]

    @Test(arguments: sampleActions)
    func macroRoundTripsThroughJSON(action: MacroAction) throws {
        let macro = Self.macro(named: "Test", action: action)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        let data = try encoder.encode(macro)
        let decoded = try decoder.decode(Macro.self, from: data)
        #expect(decoded == macro)
    }

    @Test func scriptActionsForceRequiresConfirmation() {
        let appleScript = Self.macro(named: "AS", action: .appleScript(source: "beep"))
        #expect(appleScript.requiresConfirmation)
        #expect(appleScript.isScript)

        let shell = Self.macro(named: "Shell", action: .shellCommand(command: "ls"))
        #expect(shell.requiresConfirmation)
        #expect(shell.isScript)
    }

    @Test func nonScriptActionsDoNotForceRequiresConfirmation() {
        let launch = Macro(
            name: "Launch",
            icon: "app",
            action: .launchApp(bundleID: "com.apple.Safari", activateIfRunning: true),
            page: 0,
            order: 0,
            requiresConfirmation: false
        )
        #expect(!launch.requiresConfirmation)
        #expect(!launch.isScript)
    }

    @Test func explicitRequiresConfirmationIsHonoredForNonScriptActions() {
        let macro = Macro(
            name: "Confirm me",
            icon: "app",
            action: .recenterLikeLaunch(),
            page: 0,
            order: 0,
            requiresConfirmation: true
        )
        #expect(macro.requiresConfirmation)
    }

    @Test func macroActionEncodesAsCaseKeyedObject() throws {
        let action = MacroAction.launchApp(bundleID: "com.apple.Safari", activateIfRunning: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(action)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?.keys.first == "launchApp")
    }

    @Test func macroDocumentRoundTrips() throws {
        let doc = MacroDocument(revision: 3, macros: [Self.macro(named: "One", action: .recenterLikeLaunch())])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        let data = try encoder.encode(doc)
        let decoded = try decoder.decode(MacroDocument.self, from: data)
        #expect(decoded == doc)
        #expect(decoded.schema == MacroDocument.schemaName)
    }

    @Test func macroInvokeAndResultRoundTrip() throws {
        let invoke = MacroInvoke(id: UUID(), confirmed: true)
        let invokeData = try ProtocolJSON.makeEncoder().encode(invoke)
        let decodedInvoke = try ProtocolJSON.makeDecoder().decode(MacroInvoke.self, from: invokeData)
        #expect(decodedInvoke == invoke)

        let result = MacroResult(ref: 5, id: UUID(), ok: false, message: "Blocked", code: .blockedByPolicy)
        let resultData = try ProtocolJSON.makeEncoder().encode(result)
        let decodedResult = try ProtocolJSON.makeDecoder().decode(MacroResult.self, from: resultData)
        #expect(decodedResult == result)
    }

    // MARK: - MacroValidator

    @Test func validatorAcceptsAWellFormedList() throws {
        let macros = (0..<3).map { Self.macro(named: "Macro \($0)", action: .recenterLikeLaunch(), page: 0, order: $0) }
        try MacroValidator.validate(all: macros)
    }

    @Test func validatorRejectsTooManyMacros() {
        let macros = (0..<(ProtocolConstants.macroMaxTotal + 1)).map {
            Self.macro(named: "M\($0)", action: .recenterLikeLaunch(), page: $0 % ProtocolConstants.macroMaxPages, order: $0)
        }
        #expect(throws: MacroValidationError.self) {
            try MacroValidator.validate(all: macros)
        }
    }

    @Test func validatorRejectsTooManyOnOnePage() {
        let macros = (0..<(ProtocolConstants.macroMaxPerPage + 1)).map {
            Self.macro(named: "M\($0)", action: .recenterLikeLaunch(), page: 0, order: $0)
        }
        #expect(throws: MacroValidationError.self) {
            try MacroValidator.validate(all: macros)
        }
    }

    @Test func validatorRejectsDuplicateNamesCaseInsensitively() {
        let macros = [
            Self.macro(named: "Spotlight", action: .recenterLikeLaunch(), page: 0, order: 0),
            Self.macro(named: "SPOTLIGHT", action: .recenterLikeLaunch(), page: 0, order: 1),
        ]
        #expect(throws: MacroValidationError.self) {
            try MacroValidator.validate(all: macros)
        }
    }

    @Test func validatorRejectsEmptyName() {
        let macro = Self.macro(named: "", action: .recenterLikeLaunch())
        #expect(throws: MacroValidationError.self) {
            try MacroValidator.validate(macro)
        }
    }

    @Test func validatorRejectsNameOver24Characters() {
        let macro = Self.macro(named: String(repeating: "a", count: 25), action: .recenterLikeLaunch())
        #expect(throws: MacroValidationError.self) {
            try MacroValidator.validate(macro)
        }
    }

    @Test func validatorRejectsInvalidPage() {
        let macro = Self.macro(named: "Bad page", action: .recenterLikeLaunch(), page: 6)
        #expect(throws: MacroValidationError.self) {
            try MacroValidator.validate(macro)
        }
    }

    @Test func validatorRejectsOversizedShellCommand() {
        let macro = Self.macro(named: "Big shell", action: .shellCommand(command: String(repeating: "x", count: ProtocolConstants.macroShellCommandMaxBytes + 1)))
        #expect(throws: MacroValidationError.self) {
            try MacroValidator.validate(macro)
        }
    }

    @Test func validatorRejectsOversizedAppleScript() {
        let macro = Self.macro(named: "Big script", action: .appleScript(source: String(repeating: "x", count: ProtocolConstants.macroScriptMaxBytes + 1)))
        #expect(throws: MacroValidationError.self) {
            try MacroValidator.validate(macro)
        }
    }

    @Test func validatorRejectsTooManySequenceSteps() {
        let steps = (0..<(ProtocolConstants.macroSequenceMaxSteps + 1)).map { _ in SequenceStep.text("a") }
        let macro = Self.macro(named: "Long sequence", action: .keySequence(steps: steps, interStepDelayMs: 0))
        #expect(throws: MacroValidationError.self) {
            try MacroValidator.validate(macro)
        }
    }

    @Test func validatorRejectsSequenceDelayOutOfRange() {
        let macro = Self.macro(named: "Bad delay", action: .keySequence(steps: [.text("a")], interStepDelayMs: 5000))
        #expect(throws: MacroValidationError.self) {
            try MacroValidator.validate(macro)
        }
    }

    @Test func validatorRejectsOversizedURL() {
        let hugePath = String(repeating: "a", count: ProtocolConstants.macroURLMaxBytes)
        let macro = Self.macro(named: "Big URL", action: .openURL(url: URL(string: "https://example.com/\(hugePath)")!))
        #expect(throws: MacroValidationError.self) {
            try MacroValidator.validate(macro)
        }
    }

    @Test func macroTintCoversAllTwelveNamedColors() {
        #expect(MacroTint.allCases.count == 12)
    }
}

private extension MacroAction {
    /// A neutral, always-valid action for tests that don't care about the action kind.
    static func recenterLikeLaunch() -> MacroAction {
        .launchApp(bundleID: "com.apple.Finder", activateIfRunning: false)
    }
}
