// Commands/Bench.swift
// `aircontrol-cli bench [--seconds 10] [--rate 120]` — streams synthetic motion at `rate` Hz while
// heartbeats (spec §3.4.6) and UDP probes (spec §3.5.8) run on their normal cadences, then prints the
// `SessionStats` snapshot (spec §8.2's p50/p95 RTT, fallback state) `ClientSession.currentStats()`
// produces — the same numbers the apps' Latency HUD shows, for the PRD latency metric
// (`scripts/latency-rig/`).
import AirControlCore
import AirControlProtocol
import ArgumentParser
import Foundation

struct Bench: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Measure round-trip latency and motion throughput against a connected host."
    )

    @OptionGroup var hostOptions: HostOptions

    @Option(help: "Duration of the benchmark, in seconds.")
    var seconds: Double = 10

    @Option(help: "Synthetic motion send rate, in Hz.")
    var rate: Double = 120

    @Flag(help: "Print the result as JSON.")
    var json: Bool = false

    func run() async throws {
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

        let motionIntervalNanos = rate > 0 ? UInt64(1_000_000_000 / rate) : 16_000_000
        let heartbeatIntervalNanos = UInt64(ProtocolConstants.heartbeatIntervalMs) * 1_000_000
        let probeIntervalNanos = UInt64(ProtocolConstants.probeIntervalMs) * 1_000_000

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            }
            group.addTask {
                while !Task.isCancelled {
                    try? await session.sendHeartbeat()
                    try? await Task.sleep(nanoseconds: heartbeatIntervalNanos)
                }
            }
            group.addTask {
                while !Task.isCancelled {
                    try? await session.sendProbe()
                    try? await Task.sleep(nanoseconds: probeIntervalNanos)
                }
            }
            group.addTask {
                var phase = 0.0
                while !Task.isCancelled {
                    phase += 0.1
                    let payload = MotionPayload(
                        source: .externalPointer,
                        samples: 1,
                        timestamp: CLIRuntime.nowMicros(),
                        dxPoints: sin(phase),
                        dyPoints: cos(phase),
                        scrollXPoints: 0,
                        scrollYPoints: 0
                    )
                    try? await session.sendMotion(payload)
                    try? await Task.sleep(nanoseconds: motionIntervalNanos)
                }
            }
            // The timeout task finishes first (the loops never throw or return on their own);
            // cancelling the rest lets them exit their `while !Task.isCancelled` loops cleanly.
            try await group.next()
            group.cancelAll()
        }

        let stats = await session.currentStats()
        report(stats)
        await session.close(reason: .userQuit)
    }

    private func report(_ stats: SessionStats) {
        if json {
            let payload: [String: Any] = [
                "rttP50Ms": (stats.rttP50 ?? 0) * 1000,
                "rttP95Ms": (stats.rttP95 ?? 0) * 1000,
                "lossPercent": stats.lossPercent,
                "motionRatePerSecond": stats.motionRatePerSecond,
                "fallbackEngaged": stats.isFallbackEngaged,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) {
                print(String(data: data, encoding: .utf8) ?? "{}")
            }
        } else {
            print("─── bench (\(Int(seconds))s @ \(Int(rate))Hz) ───")
            print(String(format: "  rtt p50   %6.2f ms", (stats.rttP50 ?? 0) * 1000))
            print(String(format: "  rtt p95   %6.2f ms", (stats.rttP95 ?? 0) * 1000))
            print(String(format: "  loss      %6.2f %%", stats.lossPercent))
            print(String(format: "  motion/s  %6.1f", stats.motionRatePerSecond))
            print("  fallback  \(stats.isFallbackEngaged ? "engaged (TCP)" : "normal (UDP)")")
        }
    }
}
