// Tests for Services/MomentumEngine/MomentumEngine.swift. spec §3.6.3.
// Uses `scheduleRealTimer: false` and drives `tick(dt:)` manually — a deterministic stand-in for the
// real 60 Hz `DispatchSourceTimer` (the assignment's "manual clock/tick").
import AirControlFilters
import Foundation
import Dispatch
import Testing
@testable import Air_Control

@Suite struct MomentumEngineTests {
    private func makeEngine(tau: TimeInterval = MomentumEngine.defaultTau) -> (MomentumEngine, RecordingEventPoster) {
        let poster = RecordingEventPoster()
        let queue = DispatchSerialQueue(label: "test.momentum", qos: .userInteractive)
        let engine = MomentumEngine(poster: poster, source: nil, queue: queue, tau: tau, scheduleRealTimer: false)
        return (engine, poster)
    }

    @Test func firstTickAfterStartIsBeginPhase() async {
        let (engine, poster) = makeEngine()
        await engine.start(velocity: Vector2(x: 0, y: 1000), gain: 1.0)
        let tick = await engine.tick(dt: 1.0 / 60.0)
        #expect(tick?.phase == .begin)
        #expect(poster.lastEvent?.scrollMomentumPhase == 1)
    }

    @Test func decaysThenEndsWhenBelowStopThreshold() async {
        let (engine, poster) = makeEngine(tau: 0.05) // fast decay so the test doesn't need many ticks
        await engine.start(velocity: Vector2(x: 0, y: 600), gain: 1.0)

        var phases: [MomentumPhase] = []
        for _ in 0..<60 {
            guard let tick = await engine.tick(dt: 1.0 / 60.0) else { break }
            phases.append(tick.phase)
            if tick.phase == .end { break }
        }

        #expect(phases.first == .begin)
        #expect(phases.last == .end)
        #expect(phases.dropFirst().dropLast().allSatisfy { $0 == .continue })
        #expect(await !engine.isActive)
        #expect(poster.events.last?.scrollMomentumPhase == 3)
    }

    @Test func tickAfterEndReturnsNilAndPostsNothingMore() async {
        let (engine, poster) = makeEngine(tau: 0.01)
        await engine.start(velocity: Vector2(x: 0, y: 400), gain: 1.0)
        while let tick = await engine.tick(dt: 1.0 / 60.0), tick.phase != .end {}
        let countAfterEnd = poster.events.count
        let next = await engine.tick(dt: 1.0 / 60.0)
        #expect(next == nil)
        #expect(poster.events.count == countAfterEnd)
    }

    @Test func cancelWhileActivePostsAnImmediateEndTick() async {
        let (engine, poster) = makeEngine()
        await engine.start(velocity: Vector2(x: 0, y: 1000), gain: 1.0)
        _ = await engine.tick(dt: 1.0 / 60.0) // begin
        poster.removeAll()

        await engine.cancel()

        #expect(await !engine.isActive)
        #expect(poster.lastEvent?.scrollMomentumPhase == 3)
    }

    @Test func cancelWhileInactiveIsANoOp() async {
        let (engine, poster) = makeEngine()
        await engine.cancel()
        #expect(poster.events.isEmpty)
    }

    @Test func horizontalVelocityRoutesToWheel2() async {
        let (engine, poster) = makeEngine()
        await engine.start(velocity: Vector2(x: 1000, y: 0), gain: 1.0)
        _ = await engine.tick(dt: 1.0 / 60.0)
        #expect((poster.lastEvent?.scrollWheel2 ?? 0) != 0)
        #expect(poster.lastEvent?.scrollWheel1 == 0)
    }
}
