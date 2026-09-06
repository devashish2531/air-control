// Tests for `DefaultMacroActionExecutor` action dispatch (spec §5.5.4). Kinds that would have a real
// visible side effect if they succeeded (`launchApp`, `openURL`, real Shortcuts/scripts) are only
// exercised down the *rejection* paths here (no app launched, no browser opened, no process spawned)
// — `ScriptRunnerTests` and `MacroEngineTests` cover the process-based kinds' happy paths with
// harmless commands (`/bin/echo`, `/bin/sleep`) instead.
import Testing
@testable import Air_Control
import AirControlProtocol
import Foundation

@Suite struct MacroActionExecutorTests {
    @Test func keyComboForwardsToTheKeyEmitter() async throws {
        let emitter = MockKeyEventEmitter()
        let executor = DefaultMacroActionExecutor(keyEmitter: emitter)

        let outcome = await executor.execute(.keyCombo(modifiers: [.command, .shift], keyCode: VirtualKey.kVK_ANSI_4, keyLabel: "⌘⇧4"))

        #expect(outcome.ok)
        let pressed = await emitter.pressedKeys
        #expect(pressed.count == 1)
        #expect(pressed.first?.virtualKey == VirtualKey.kVK_ANSI_4)
        #expect(pressed.first?.modifiers == [.command, .shift])
    }

    @Test func keySequenceRunsEachStepInOrder() async throws {
        let emitter = MockKeyEventEmitter()
        let executor = DefaultMacroActionExecutor(keyEmitter: emitter)

        let steps: [SequenceStep] = [
            .combo(modifiers: [.command], keyCode: VirtualKey.kVK_ANSI_C, keyLabel: "⌘C"),
            .text("hello"),
            .combo(modifiers: [.command], keyCode: VirtualKey.kVK_ANSI_V, keyLabel: "⌘V"),
        ]
        let outcome = await executor.execute(.keySequence(steps: steps, interStepDelayMs: 0))

        #expect(outcome.ok)
        let pressed = await emitter.pressedKeys
        let typed = await emitter.typedText
        #expect(pressed.map(\.virtualKey) == [VirtualKey.kVK_ANSI_C, VirtualKey.kVK_ANSI_V])
        #expect(typed == ["hello"])
    }

    @Test func launchAppWithUnknownBundleIDFails() async throws {
        let emitter = MockKeyEventEmitter()
        let executor = DefaultMacroActionExecutor(keyEmitter: emitter)

        let outcome = await executor.execute(.launchApp(bundleID: "com.aircontrol.definitely-not-installed-\(UUID().uuidString)", activateIfRunning: false))

        #expect(!outcome.ok)
        #expect(!outcome.timedOut)
    }

    @Test func openURLRejectsAnUnregisteredScheme() async throws {
        let emitter = MockKeyEventEmitter()
        let executor = DefaultMacroActionExecutor(keyEmitter: emitter)

        let url = URL(string: "aircontrol-test-scheme-\(UUID().uuidString.prefix(8))://nowhere")!
        let outcome = await executor.execute(.openURL(url: url))

        #expect(!outcome.ok)
        #expect(outcome.message.contains("No app is registered"))
    }

    @Test func runShortcutWithMissingBinaryOrNameStillReturnsAnOutcomeNotACrash() async throws {
        let emitter = MockKeyEventEmitter()
        let executor = DefaultMacroActionExecutor(keyEmitter: emitter)

        // `/usr/bin/shortcuts` exists on macOS 15, but a nonexistent shortcut name exits non-zero
        // rather than hanging — this exercises the process-based dispatch path end to end quickly.
        let outcome = await executor.execute(.runShortcut(name: "Definitely Not A Real Shortcut \(UUID().uuidString)"))
        #expect(!outcome.ok)
        #expect(!outcome.timedOut)
    }

    @Test func shellCommandRunsAndCapturesOutput() async throws {
        let emitter = MockKeyEventEmitter()
        let executor = DefaultMacroActionExecutor(keyEmitter: emitter)

        let outcome = await executor.execute(.shellCommand(command: "echo from-shell"))
        #expect(outcome.ok)
        #expect(outcome.message.contains("from-shell"))
    }

    @Test func appleScriptFailureIsReportedAsNotOK() async throws {
        let emitter = MockKeyEventEmitter()
        let executor = DefaultMacroActionExecutor(keyEmitter: emitter)

        // Deliberately invalid AppleScript so `osascript` exits non-zero without needing any TCC
        // automation permission (no `tell application` target).
        let outcome = await executor.execute(.appleScript(source: "this is not valid applescript §§§"))
        #expect(!outcome.ok)
    }
}
