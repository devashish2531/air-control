// spec §5.5.4 (execution table) + §3.3 architecture "ScriptRunner" row: "`Process` for
// `/usr/bin/osascript -`, `/bin/zsh -c`, `/usr/bin/shortcuts run`; reduced environment; one concurrent
// process, 30/60 s timeout → `terminate()` then `kill -9` after 2 s, output capped at 4 KB, first 120
// chars into `macroResult.message`; **never** `NSAppleScript` in-process (ADR-012)".
//
// This type owns exactly one subprocess invocation end to end (launch → capture → timeout → kill
// escalation). It knows nothing about macros, gating, or serialization of "one script at a time" —
// that is `MacroEngine`'s job (spec §7.6 "Script processes: 1 concurrent"). Kept as a plain `Sendable`
// struct (no actor) since every stored property is immutable and each `run` call is fully self-contained.
import Foundation

/// A thread-safe one-shot latch `ScriptRunner.run` uses to record whether the timeout watchdog actually
/// fired, independent of which task happens to resolve the internal race first. `@unchecked Sendable`:
/// the only mutable state is behind `NSLock`.
private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _fired = false

    var fired: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _fired
    }

    func mark() {
        lock.lock()
        _fired = true
        lock.unlock()
    }
}

/// Runs one subprocess to completion, truncated output, and a killable timeout. Spec §5.5.4's
/// `/usr/bin/osascript`, `/bin/zsh`, `/usr/bin/shortcuts` invocations all funnel through this one type.
public struct ScriptRunner: Sendable {
    public struct Result: Sendable, Equatable {
        /// The process's exit code, or `-1` for "never launched" / "killed by our own watchdog".
        public var exitCode: Int32
        /// Combined stdout+stderr (spec §5.5.4: "Results → `macroResult` with `message` = first 120
        /// chars of stdout or stderr" — the two streams are not distinguished at the `macroResult` layer,
        /// so capturing them combined loses nothing a caller needs), truncated to `outputCapBytes`.
        public var output: String
        /// `true` iff the timeout elapsed before the process exited on its own (the watchdog had to
        /// `terminate()`/`kill -9` it) — lets `MacroEngine` map to `macroResult.code == .timeout` instead
        /// of `.failed` regardless of which exit races back first internally.
        public var timedOut: Bool
        /// `true` iff `Process.run()` itself threw (bad executable path, no permission, etc.) rather than
        /// the process launching and exiting/timing out.
        public var launchFailed: Bool

        public init(exitCode: Int32, output: String, timedOut: Bool, launchFailed: Bool = false) {
            self.exitCode = exitCode
            self.output = output
            self.timedOut = timedOut
            self.launchFailed = launchFailed
        }
    }

    /// spec §5.5.4: "output capped at 4 KB" (the 120-char `macroResult.message` truncation happens one
    /// layer up, in `MacroEngine`, from this already-4KB-capped text).
    public static let outputCapBytes = 4096

    /// Grace period between `terminate()` (SIGTERM) and escalating to `kill -9` (spec §5.5.4).
    public static let killEscalationDelay: Duration = .seconds(2)

    public init() {}

    /// Launches `executable arguments`, waits up to `timeout`, and on timeout sends `terminate()` then
    /// `SIGKILL` after `killEscalationDelay`. `standardInput` is `/dev/null` unless `stdin` is supplied
    /// (osascript's `-` form reads the script source on stdin).
    public func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        currentDirectoryURL: URL? = nil,
        stdin: Data? = nil,
        timeout: Duration
    ) async -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        if let currentDirectoryURL {
            process.currentDirectoryURL = currentDirectoryURL
        }

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let inputPipe: Pipe?
        if stdin != nil {
            let pipe = Pipe()
            process.standardInput = pipe
            inputPipe = pipe
        } else {
            process.standardInput = FileHandle.nullDevice
            inputPipe = nil
        }

        do {
            try process.run()
        } catch {
            return Result(exitCode: -1, output: "", timedOut: false, launchFailed: true)
        }

        if let stdin, let inputPipe {
            // Best-effort write; a script that never reads stdin would otherwise block us on a full pipe
            // buffer, but macro scripts are short strings (≤ 8 KB, spec §5.5.1), well under the pipe's
            // 64 KB buffer, so a synchronous write here cannot deadlock against the child.
            inputPipe.fileHandleForWriting.write(stdin)
            try? inputPipe.fileHandleForWriting.close()
        }

        let timeoutFlag = TimeoutFlag()

        // Race "process exited" against "timeout elapsed", but let the loser keep running to completion
        // instead of returning early: if we returned as soon as the *first* result arrived, the losing
        // task's `terminate()`/`kill -9` escalation (in the timeout branch) would still be in flight when
        // the function returns, and structured concurrency requires `withTaskGroup` to await every child
        // task before the closure returns anyway — resolving that only from the *winning* branch would
        // deadlock (the loser can't be abandoned; it must be drained via `for await` before we may read
        // `pipe.fileHandleForReading` and produce a final value).
        let exitCode: Int32 = await withTaskGroup(of: Int32?.self) { group in
            group.addTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<Int32?, Never>) in
                    process.terminationHandler = { finished in
                        continuation.resume(returning: finished.terminationStatus)
                    }
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    // Cancelled because the process already exited on its own — nothing to do.
                    return nil
                }
                timeoutFlag.mark()
                process.terminate()
                try? await Task.sleep(for: Self.killEscalationDelay)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                return nil
            }

            var resolvedExitCode: Int32 = -1
            for await value in group {
                if let value {
                    resolvedExitCode = value
                    group.cancelAll() // lets a still-sleeping timeout task bail out immediately
                }
            }
            return resolvedExitCode
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let capped = data.prefix(Self.outputCapBytes)
        let text = String(data: capped, encoding: .utf8) ?? String(decoding: capped, as: UTF8.self)

        return Result(exitCode: exitCode, output: text, timedOut: timeoutFlag.fired)
    }
}
