// Commands/Replay.swift
// `aircontrol-cli replay <file.jsonl>` — replays recorded events with their original timing. Each line
// is one JSON object `{"kind": "move"|"click"|"scroll", "dx": <points>, "dy": <points>, "t": <seconds
// since recording start>}`; `t` is used only to reproduce the original inter-event spacing (motion
// samples still go out one datagram per line, spec §3.5.2 — this command does not re-coalesce them).
import AirControlCore
import AirControlProtocol
import ArgumentParser
import Foundation

private struct RecordedEvent: Decodable {
    var kind: String
    var dx: Double?
    var dy: Double?
    var t: Double
}

struct Replay: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Replay a recorded .jsonl event stream with its original timing."
    )

    @OptionGroup var hostOptions: HostOptions

    @Argument(help: "Path to a .jsonl file of {kind, dx, dy, t} events.")
    var file: String

    func run() async throws {
        let url = URL(fileURLWithPath: file)
        guard let contents = FileManager.default.contents(atPath: url.path),
              let text = String(data: contents, encoding: .utf8)
        else {
            throw CLIError("could not read '\(file)'")
        }

        let decoder = JSONDecoder()
        var events: [RecordedEvent] = []
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            guard let data = line.data(using: .utf8), let event = try? decoder.decode(RecordedEvent.self, from: data) else {
                FileHandle.standardError.write("warning: skipping unparseable line \(index + 1)\n".data(using: .utf8)!)
                continue
            }
            events.append(event)
        }
        guard !events.isEmpty else {
            throw CLIError("'\(file)' contained no parseable events")
        }

        let pinnedFingerprint = try CLIRuntime.resolvePinnedFingerprint(hostOptions)
        let (session, control, _) = try await CLIRuntime.openSession(
            host: hostOptions.host,
            controlPort: hostOptions.port,
            pinnedFingerprint: pinnedFingerprint,
            verbose: hostOptions.verbose
        )
        do {
            _ = try await session.connect()
        } catch {
            await control.close()
            throw CLIError("connect failed: \(error)")
        }

        var previousT = events[0].t
        var sent = 0
        for event in events {
            let delay = max(0, event.t - previousT)
            previousT = event.t
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            switch event.kind {
            case "move":
                let payload = MotionPayload(
                    source: .externalPointer,
                    samples: 1,
                    timestamp: CLIRuntime.nowMicros(),
                    dxPoints: event.dx ?? 0,
                    dyPoints: event.dy ?? 0,
                    scrollXPoints: 0,
                    scrollYPoints: 0
                )
                try await session.sendMotion(payload)
            case "scroll":
                let payload = MotionPayload(
                    flags: [.scrollBegan, .scrollEnded],
                    source: .externalPointer,
                    samples: 1,
                    timestamp: CLIRuntime.nowMicros(),
                    dxPoints: 0,
                    dyPoints: 0,
                    scrollXPoints: event.dx ?? 0,
                    scrollYPoints: event.dy ?? 0
                )
                try await session.sendMotion(payload)
            case "click":
                try await session.sendClick(AirControlProtocol.Click(button: .left, action: .tap, count: 1, modifiers: []))
            default:
                continue
            }
            sent += 1
        }
        print("Replayed \(sent)/\(events.count) event(s) from \(file).")
        await session.close(reason: .userQuit)
    }
}
