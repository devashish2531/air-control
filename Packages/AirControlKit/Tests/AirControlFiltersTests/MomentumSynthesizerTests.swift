import Testing
import Foundation
@testable import AirControlFilters

private struct MomentumVector: Decodable {
    struct Vec: Decodable { let x: Double; let y: Double }
    struct Tick: Decodable { let phase: String; let dx: Double; let dy: Double }
    let tau: Double
    let dt: Double
    let gain: Double
    let initialVelocity: Vec
    let ticks: [Tick]
}

@Suite struct MomentumSynthesizerTests {
    private static func loadVector() throws -> MomentumVector {
        let url = try #require(
            Bundle.module.url(forResource: "momentum", withExtension: "json", subdirectory: "Vectors")
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MomentumVector.self, from: data)
    }

    @Test func decaySequenceMatchesFrozenVector() throws {
        let vector = try Self.loadVector()
        var synth = MomentumSynthesizer(tau: vector.tau)
        synth.start(velocity: Vector2(x: vector.initialVelocity.x, y: vector.initialVelocity.y), gain: vector.gain)

        var produced: [MomentumTick] = []
        for _ in vector.ticks {
            guard let tick = synth.tick(dt: vector.dt) else { break }
            produced.append(tick)
        }

        #expect(produced.count == vector.ticks.count)
        for (i, expected) in vector.ticks.enumerated() where i < produced.count {
            let actual = produced[i]
            #expect(actual.delta.dx == expected.dx, "tick \(i) dx")
            #expect(actual.delta.dy == expected.dy, "tick \(i) dy")
            switch expected.phase {
            case "begin": #expect(actual.phase == .begin, "tick \(i) phase")
            case "continue": #expect(actual.phase == .continue, "tick \(i) phase")
            case "end": #expect(actual.phase == .end, "tick \(i) phase")
            default: Issue.record("unknown phase in vector: \(expected.phase)")
            }
        }
    }

    @Test func inactiveSynthesizerReturnsNilTick() {
        var synth = MomentumSynthesizer()
        #expect(synth.tick(dt: 1.0 / 60.0) == nil)
    }

    @Test func firstTickAfterStartIsAlwaysBegin() {
        var synth = MomentumSynthesizer()
        synth.start(velocity: Vector2(x: 400, y: 0), gain: 1.0)
        let tick = synth.tick(dt: 1.0 / 60.0)
        #expect(tick?.phase == .begin)
    }

    @Test func cancelStopsFurtherTicks() {
        var synth = MomentumSynthesizer()
        synth.start(velocity: Vector2(x: 400, y: 0), gain: 1.0)
        _ = synth.tick(dt: 1.0 / 60.0)
        synth.cancel()
        #expect(synth.active == false)
        #expect(synth.tick(dt: 1.0 / 60.0) == nil)
    }

    @Test func lowerVelocityFlingEndsInFewerTicks() {
        var slow = MomentumSynthesizer()
        var fast = MomentumSynthesizer()
        slow.start(velocity: Vector2(x: 310, y: 0), gain: 1.0)
        fast.start(velocity: Vector2(x: 2000, y: 0), gain: 1.0)

        func countTicks(_ synth: inout MomentumSynthesizer) -> Int {
            var count = 0
            while let tick = synth.tick(dt: 1.0 / 60.0) {
                count += 1
                if tick.phase == .end { break }
                if count > 2000 { break }
            }
            return count
        }

        let slowCount = countTicks(&slow)
        let fastCount = countTicks(&fast)
        #expect(fastCount > slowCount)
    }

    @Test func decayIsDeterministicGivenSameTickSequence() {
        var a = MomentumSynthesizer()
        var b = MomentumSynthesizer()
        a.start(velocity: Vector2(x: 900, y: 300), gain: 1.22)
        b.start(velocity: Vector2(x: 900, y: 300), gain: 1.22)

        for _ in 0..<30 {
            let ta = a.tick(dt: 1.0 / 60.0)
            let tb = b.tick(dt: 1.0 / 60.0)
            #expect(ta == tb)
        }
    }

    @Test func endsWhenBelowStopThreshold() {
        var synth = MomentumSynthesizer()
        synth.start(velocity: Vector2(x: 1, y: 0), gain: 1.0) // already below threshold immediately
        let first = synth.tick(dt: 1.0 / 60.0)
        #expect(first?.phase == .begin)
        let second = synth.tick(dt: 1.0 / 60.0)
        #expect(second?.phase == .end)
        #expect(synth.active == false)
    }
}
