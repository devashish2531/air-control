@testable import Air_Control
import AirControlProtocol
import Foundation

/// Test double for `MacroActionExecuting` — records every action it was asked to run and returns a
/// scripted `MacroExecutionOutcome`, so `MacroEngine` gating tests never spawn a real subprocess or
/// touch `NSWorkspace`.
actor MockMacroActionExecutor: MacroActionExecuting {
    private(set) var executedActions: [MacroAction] = []
    var outcomeToReturn: MacroExecutionOutcome = .success("ok")

    func execute(_ action: MacroAction) async -> MacroExecutionOutcome {
        executedActions.append(action)
        return outcomeToReturn
    }
}

/// Test double for `KeyEventEmitting` — records presses/typed text instead of touching a real
/// injector.
actor MockKeyEventEmitter: KeyEventEmitting {
    private(set) var pressedKeys: [(virtualKey: UInt16, modifiers: KeyModifiers)] = []
    private(set) var typedText: [String] = []

    func press(virtualKey: UInt16, modifiers: KeyModifiers) async {
        pressedKeys.append((virtualKey, modifiers))
    }

    func typeText(_ text: String) async {
        typedText.append(text)
    }
}
