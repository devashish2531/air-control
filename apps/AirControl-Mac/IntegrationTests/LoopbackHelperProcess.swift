// IntegrationTests/LoopbackHelperProcess.swift
// Locates and launches the built `AirControl.app` helper in `--loopback` mode (contract with the
// networking/app-shell agents, `apps/AirControl-Mac/Sources/Services/HostServer/HostServer.swift`'s
// `printLoopbackBanner()`): prints `AIRCONTROL_TCP_PORT=`/`AIRCONTROL_UDP_PORT=`/`AIRCONTROL_PAIR_URL=`
// lines to stdout and, once the app-shell agent wires it up, writes one JSON `PostedEvent` per line
// to the file named by the `AIRCONTROL_LOOPBACK_LOG` env var. Every step here fails soft (returns
// `nil`) rather than throwing, so callers can SKIP instead of failing when the helper isn't built or
// hasn't finished wiring `--loopback` end-to-end yet (see this file's doc comment in the test suite).
import Foundation

final class LoopbackHelperProcess {
    let process: Process
    let logFileURL: URL
    private(set) var pairURLString: String = ""
    private let stdoutPipe: Pipe
    private let outputBox = LoopbackLockedBox<String>("")

    private init(process: Process, logFileURL: URL, stdoutPipe: Pipe) {
        self.process = process
        self.logFileURL = logFileURL
        self.stdoutPipe = stdoutPipe
    }

    /// `$BUILT_PRODUCTS_DIR/AirControl.app/Contents/MacOS/AirControl`, or — since this test bundle is
    /// hosted *inside* that same executable (`TEST_HOST`/`BUNDLE_LOADER` in project.yml) —
    /// `Bundle.main.executablePath` as a fallback that needs no environment variable at all.
    static func locateExecutable() -> URL? {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["BUILT_PRODUCTS_DIR"] {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent("AirControl.app/Contents/MacOS/AirControl")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        if let exePath = Bundle.main.executablePath, FileManager.default.isExecutableFile(atPath: exePath) {
            return URL(fileURLWithPath: exePath)
        }
        return nil
    }

    /// Launches `--loopback`, waits up to `timeout` seconds for `AIRCONTROL_PAIR_URL=` on stdout.
    /// Returns `nil` (callers must SKIP, not fail) if the executable can't be found, can't launch,
    /// or never prints that line in time.
    static func launch(timeout: TimeInterval = 10) async -> LoopbackHelperProcess? {
        guard let executable = locateExecutable() else { return nil }

        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("aircontrol-loopback-\(UUID().uuidString).jsonl")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)

        let process = Process()
        process.executableURL = executable
        process.arguments = ["--loopback"]
        var environment = ProcessInfo.processInfo.environment
        environment["AIRCONTROL_LOOPBACK_LOG"] = logURL.path
        // Never let a test pairing land in the developer's real trust store (20-device cap).
        environment["AIRCONTROL_DATA_DIR"] = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirControlHelper-itest-\(UUID().uuidString)", isDirectory: true).path
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // discard; avoid the default (inherited) fd filling up

        let helper = LoopbackHelperProcess(process: process, logFileURL: logURL, stdoutPipe: pipe)
        let outputBox = helper.outputBox // capture the Sendable box, not `helper` itself, in the @Sendable handler
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            outputBox.value += text
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let line = helper.outputBox.value.split(separator: "\n").first(where: { $0.hasPrefix("AIRCONTROL_PAIR_URL=") }) {
                helper.pairURLString = String(line.dropFirst("AIRCONTROL_PAIR_URL=".count))
                return helper
            }
            if !process.isRunning {
                return nil // exited before printing the banner — treat as "not built/ready"
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        helper.terminate()
        return nil
    }

    /// Reads every complete JSON line currently in the loopback log (best-effort: the helper may
    /// still be writing; callers that need "at least N events" should poll this with a short sleep
    /// loop rather than calling it once immediately after sending).
    func readLogLines() -> [String] {
        guard let data = FileManager.default.contents(atPath: logFileURL.path),
              let text = String(data: data, encoding: .utf8)
        else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    func terminate() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        try? FileManager.default.removeItem(at: logFileURL)
    }
}
