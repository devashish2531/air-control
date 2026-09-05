// Tests for `ScriptRunner` (spec §5.5.4 execution table: launch, capture, timeout + kill escalation,
// output truncation).
import Testing
@testable import Air_Mouse
import Foundation

@Suite struct ScriptRunnerTests {
    @Test func echoCapturesStdout() async throws {
        let runner = ScriptRunner()
        let result = await runner.run(
            executable: "/bin/echo",
            arguments: ["hello", "world"],
            environment: [:],
            timeout: .seconds(5)
        )
        #expect(result.exitCode == 0)
        #expect(result.output == "hello world\n")
        #expect(!result.timedOut)
        #expect(!result.launchFailed)
    }

    @Test func nonZeroExitCodeIsReported() async throws {
        let runner = ScriptRunner()
        // `zsh -c 'exit 7'` is a reliable, fast way to get an arbitrary non-zero exit code.
        let result = await runner.run(
            executable: "/bin/zsh",
            arguments: ["-c", "exit 7"],
            environment: [:],
            timeout: .seconds(5)
        )
        #expect(result.exitCode == 7)
        #expect(!result.timedOut)
    }

    @Test func aFailingCommandReportsStderr() async throws {
        let runner = ScriptRunner()
        let result = await runner.run(
            executable: "/bin/zsh",
            arguments: ["-c", "echo oops 1>&2; exit 1"],
            environment: [:],
            timeout: .seconds(5)
        )
        #expect(result.exitCode == 1)
        #expect(result.output.contains("oops"))
    }

    @Test func unlaunchableExecutableReportsLaunchFailure() async throws {
        let runner = ScriptRunner()
        let result = await runner.run(
            executable: "/no/such/executable-\(UUID().uuidString)",
            arguments: [],
            environment: [:],
            timeout: .seconds(5)
        )
        #expect(result.launchFailed)
        #expect(!result.timedOut)
    }

    @Test func aSlowProcessIsKilledAtTheTimeout() async throws {
        let runner = ScriptRunner()
        let start = ContinuousClock.now
        let result = await runner.run(
            executable: "/bin/sleep",
            arguments: ["5"],
            environment: [:],
            timeout: .milliseconds(300)
        )
        let elapsed = ContinuousClock.now - start
        #expect(result.timedOut)
        // Killed well before the full 5 s sleep would have elapsed (generous bound for CI jitter).
        #expect(elapsed < .seconds(4))
    }

    @Test func stdinIsDeliveredToTheProcess() async throws {
        let runner = ScriptRunner()
        let result = await runner.run(
            executable: "/bin/cat",
            arguments: [],
            environment: [:],
            stdin: Data("piped in".utf8),
            timeout: .seconds(5)
        )
        #expect(result.output == "piped in")
    }

    @Test func outputIsTruncatedToTheCapBeforeReturning() async throws {
        let runner = ScriptRunner()
        // `yes` streams "y\n" forever; cap it well past `outputCapBytes` so truncation, not process
        // duration, is what's under test.
        let result = await runner.run(
            executable: "/bin/zsh",
            arguments: ["-c", "yes | head -c 100000"],
            environment: [:],
            timeout: .seconds(10)
        )
        #expect(result.output.utf8.count <= ScriptRunner.outputCapBytes)
    }

    @Test func currentDirectoryURLIsHonored() async throws {
        let runner = ScriptRunner()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let result = await runner.run(
            executable: "/bin/pwd",
            arguments: [],
            environment: [:],
            currentDirectoryURL: home,
            timeout: .seconds(5)
        )
        #expect(result.output.trimmingCharacters(in: .whitespacesAndNewlines) == home.path)
    }
}
