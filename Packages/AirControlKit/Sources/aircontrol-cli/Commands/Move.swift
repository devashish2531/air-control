// Commands/Move.swift
// `aircontrol-cli move --dx --dy [--count 1] [--rate 120]` — sends `count` motion datagrams (spec
// §3.5.2) over UDP at `rate` Hz, each carrying `(dx, dy)` points.
import AirControlCore
import AirControlProtocol
import ArgumentParser
import Foundation

struct Move: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Send pointer-motion datagrams to a connected host."
    )

    @OptionGroup var hostOptions: HostOptions

    @Option(help: "Delta X per datagram, in points.")
    var dx: Double

    @Option(help: "Delta Y per datagram, in points.")
    var dy: Double

    @Option(help: "Number of datagrams to send.")
    var count: Int = 1

    @Option(help: "Send rate in Hz.")
    var rate: Double = 120

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

        let intervalNanos = rate > 0 ? UInt64(1_000_000_000 / rate) : 0
        for _ in 0..<max(0, count) {
            let payload = MotionPayload(
                source: .externalPointer,
                samples: 1,
                timestamp: CLIRuntime.nowMicros(),
                dxPoints: dx,
                dyPoints: dy,
                scrollXPoints: 0,
                scrollYPoints: 0
            )
            try await session.sendMotion(payload)
            if intervalNanos > 0 {
                try await Task.sleep(nanoseconds: intervalNanos)
            }
        }
        try await session.sendMotionEndControl()
        print("Sent \(count) motion datagram(s): dx=\(dx) dy=\(dy) at \(rate)Hz.")
        await session.close(reason: .userQuit)
    }
}
