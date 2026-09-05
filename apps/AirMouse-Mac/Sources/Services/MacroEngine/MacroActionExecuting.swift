// spec §5.5.4 "Execution" table — per-kind implementation and timeout. `MacroActionExecuting` is the
// seam the assignment asked for ("behind a protocol so tests can inject fakes"); `DefaultMacroActionExecutor`
// is the real, production implementation `MacroEngine` uses outside of tests.
import AirMouseProtocol
import AppKit
import Foundation

/// The result of running one `MacroAction`, independent of the `MacroInvoke`/`macroResult` wire shape —
/// `MacroEngine` maps this to a `MacroResultCode` (`.ok`/`.timeout`/`.failed`) once it also knows the
/// gating outcome that happened before execution.
public struct MacroExecutionOutcome: Sendable, Equatable {
    public var ok: Bool
    public var timedOut: Bool
    /// Free-form diagnostic text — for script/Shortcut kinds this is `ScriptRunner`'s captured
    /// stdout+stderr (already capped to 4 KB); `MacroEngine` truncates to the wire's 120-char cap
    /// (spec §5.5.4: "message = first 120 chars of stdout or stderr").
    public var message: String

    public init(ok: Bool, timedOut: Bool = false, message: String = "") {
        self.ok = ok
        self.timedOut = timedOut
        self.message = message
    }

    public static func success(_ message: String = "") -> Self { .init(ok: true, message: message) }
    public static func failure(_ message: String) -> Self { .init(ok: false, message: message) }
    public static func timeout(_ message: String = "") -> Self { .init(ok: false, timedOut: true, message: message) }
}

/// Executes one already-gated `MacroAction` (spec §5.5.4's table). `MacroEngine` calls this only after
/// its own script-policy gate (§5.5.5) and "one script process at a time" serialization (§7.6) pass —
/// this protocol has no opinion on policy, only on "how do I run this action kind".
public protocol MacroActionExecuting: Sendable {
    func execute(_ action: MacroAction) async -> MacroExecutionOutcome
}

/// Thrown by the cooperative timeout wrapper used for `NSWorkspace` calls (`launchApp`) that cannot be
/// force-killed the way a subprocess can (there is no PID to `SIGKILL`) — best-effort only; a genuinely
/// wedged `NSWorkspace` call still occupies this actor's executor until it eventually returns.
struct MacroTimeoutError: Error {}

/// Races `operation` against `duration`. Not a substitute for `ScriptRunner`'s kill escalation — only
/// used for in-process AppKit calls where there is no subprocess to terminate.
func withMacroTimeout<T: Sendable>(_ duration: Duration, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw MacroTimeoutError()
        }
        guard let result = try await group.next() else { throw MacroTimeoutError() }
        group.cancelAll()
        return result
    }
}

/// Production `MacroActionExecuting`. Owns one `ScriptRunner` and forwards key events to an injected
/// `KeyEventEmitting` (the real conformer lives in the injection agent's module — see
/// `KeyEventEmitting.swift`). An actor because `NSWorkspace`/`ScriptRunner` calls should not overlap with
/// unrelated actor state, and so tests can safely construct many instances concurrently.
public actor DefaultMacroActionExecutor: MacroActionExecuting {
    private let keyEmitter: any KeyEventEmitting
    private let scriptRunner: ScriptRunner
    private let workspace: NSWorkspace
    private let homeDirectory: URL

    public init(
        keyEmitter: any KeyEventEmitting,
        scriptRunner: ScriptRunner = ScriptRunner(),
        workspace: NSWorkspace = .shared,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.keyEmitter = keyEmitter
        self.scriptRunner = scriptRunner
        self.workspace = workspace
        self.homeDirectory = homeDirectory
    }

    public func execute(_ action: MacroAction) async -> MacroExecutionOutcome {
        switch action {
        case .keyCombo(let modifiers, let keyCode, _):
            await keyEmitter.press(virtualKey: keyCode, modifiers: modifiers)
            return .success()

        case .keySequence(let steps, let interStepDelayMs):
            return await runKeySequence(steps, interStepDelayMs: interStepDelayMs)

        case .launchApp(let bundleID, let activateIfRunning):
            return await launchApp(bundleID: bundleID, activateIfRunning: activateIfRunning)

        case .openURL(let url):
            return openURL(url)

        case .runShortcut(let name):
            return await runShortcut(name: name)

        case .appleScript(let source):
            return await runAppleScript(source)

        case .shellCommand(let command):
            return await runShellCommand(command)
        }
    }

    // MARK: keyCombo / keySequence (spec §5.5.4: "`EventInjector` tap ... same path as `key`")

    private func runKeySequence(_ steps: [SequenceStep], interStepDelayMs: Int) async -> MacroExecutionOutcome {
        // spec §5.5.4 keySequence row: "total ≤ 30 s".
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        for (index, step) in steps.enumerated() {
            if ContinuousClock.now > deadline {
                return .timeout("Key sequence exceeded 30 s")
            }
            switch step {
            case .combo(let modifiers, let keyCode, _):
                await keyEmitter.press(virtualKey: keyCode, modifiers: modifiers)
            case .text(let text):
                await keyEmitter.typeText(text)
            }
            if index < steps.count - 1, interStepDelayMs > 0 {
                try? await Task.sleep(for: .milliseconds(interStepDelayMs))
            }
        }
        return .success()
    }

    // MARK: launchApp (spec §5.5.4, research A9)

    private func launchApp(bundleID: String, activateIfRunning: Bool) async -> MacroExecutionOutcome {
        if activateIfRunning,
           let running = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            running.activate()
            return .success()
        }
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
            return .failure("No app installed with bundle id \(bundleID)")
        }
        do {
            // spec §5.5.4 launchApp row: "10 s" timeout. `NSWorkspace`/`OpenConfiguration` aren't
            // `Sendable`, so rather than capture `self.workspace`/a shared `configuration` across the
            // `@Sendable` child-task boundary, the closure re-resolves `.shared` and builds a fresh
            // configuration internally (only `url`, which is `Sendable`, crosses the boundary) — this
            // app only ever has one `NSWorkspace` in practice, and this success path isn't exercised
            // by tests with an injected fake (see `MacroActionExecutorTests`'s doc comment).
            _ = try await withMacroTimeout(.seconds(10)) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                return try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            }
            return .success()
        } catch is MacroTimeoutError {
            return .timeout("Launching \(bundleID) timed out")
        } catch {
            return .failure(String(describing: error))
        }
    }

    // MARK: openURL (spec §5.5.4: "only `http`, `https`, `file` and schemes with a registered handler")

    private func openURL(_ url: URL) -> MacroExecutionOutcome {
        let alwaysAllowed: Set<String> = ["http", "https", "file"]
        let scheme = url.scheme?.lowercased() ?? ""
        let hasRegisteredHandler = workspace.urlForApplication(toOpen: url) != nil
        guard alwaysAllowed.contains(scheme) || hasRegisteredHandler else {
            return .failure("No app is registered to open \(scheme.isEmpty ? url.absoluteString : scheme + ":")")
        }
        return workspace.open(url) ? .success() : .failure("Couldn't open \(url.absoluteString)")
    }

    // MARK: Shortcuts / AppleScript / shell (spec §5.5.4, research A9, ADR-012)

    private func runShortcut(name: String) async -> MacroExecutionOutcome {
        let result = await scriptRunner.run(
            executable: "/usr/bin/shortcuts",
            arguments: ["run", name],
            environment: Self.reducedEnvironment(),
            currentDirectoryURL: homeDirectory,
            timeout: .seconds(60)
        )
        return outcome(from: result)
    }

    private func runAppleScript(_ source: String) async -> MacroExecutionOutcome {
        // spec §5.5.4: `Process("/usr/bin/osascript", ["-"])` with the source on stdin, "so a hung script
        // can be killed and the main thread never blocks" — never `NSAppleScript` in-process (ADR-012).
        let result = await scriptRunner.run(
            executable: "/usr/bin/osascript",
            arguments: ["-"],
            environment: Self.reducedEnvironment(),
            currentDirectoryURL: homeDirectory,
            stdin: Data(source.utf8),
            timeout: .seconds(30)
        )
        return outcome(from: result)
    }

    private func runShellCommand(_ command: String) async -> MacroExecutionOutcome {
        let result = await scriptRunner.run(
            executable: "/bin/zsh",
            arguments: ["-c", command],
            environment: Self.reducedEnvironment(),
            currentDirectoryURL: homeDirectory,
            timeout: .seconds(30)
        )
        return outcome(from: result)
    }

    private func outcome(from result: ScriptRunner.Result) -> MacroExecutionOutcome {
        if result.launchFailed {
            return .failure("Couldn't launch the process")
        }
        if result.timedOut {
            return .timeout(result.output)
        }
        return MacroExecutionOutcome(ok: result.exitCode == 0, message: result.output)
    }

    /// spec §5.5.4: "environment reduced to `PATH`, `HOME`, `USER`, `LANG`, `TMPDIR`".
    static func reducedEnvironment() -> [String: String] {
        var env: [String: String] = [:]
        for key in ["PATH", "HOME", "USER", "LANG", "TMPDIR"] {
            if let value = ProcessInfo.processInfo.environment[key] {
                env[key] = value
            }
        }
        return env
    }
}
