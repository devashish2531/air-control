// Commands/Scroll.swift
// `airmouse-cli scroll --dy [--dx]` — one scroll gesture: `scrollPhase{began}` → one motion datagram
// carrying the scroll deltas (spec §3.6.2: "deltas themselves travel on the motion channel") →
// `scrollPhase{ended}`.
import AirMouseCore
import AirMouseProtocol
import ArgumentParser
import Foundation

struct Scroll: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Send one scroll gesture."
    )

    @OptionGroup var hostOptions: HostOptions

    @Option(help: "Scroll delta Y, in points.")
    var dy: Double

    @Option(help: "Scroll delta X, in points.")
    var dx: Double = 0

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

        try await session.sendScrollPhase(ScrollPhase(phase: .began))
        let payload = MotionPayload(
            flags: [.scrollBegan, .scrollEnded],
            source: .externalPointer,
            samples: 1,
            timestamp: CLIRuntime.nowMicros(),
            dxPoints: 0,
            dyPoints: 0,
            scrollXPoints: dx,
            scrollYPoints: dy
        )
        try await session.sendMotion(payload)
        try await session.sendScrollPhase(ScrollPhase(phase: .ended, vx: 0, vy: 0, momentum: false))
        print("Sent scroll: dx=\(dx) dy=\(dy)")
        await session.close(reason: .userQuit)
    }
}
