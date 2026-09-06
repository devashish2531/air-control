// Tests/GyroDeltaForwardingTests.swift
// Delta → `GyroMotionSink` shape (spec §3.5.2's `source`/`flags`/`timestamp` fields as `GyroEngine`
// hands them off) and the FR-GY-008 80 ms motion-suppression-after-click window (spec §4.3.6).
import AirControlFilters
import Foundation
import Testing
import simd
@testable import Air_Control

@MainActor
@Suite struct GyroDeltaForwardingTests {
    private func makeEngine() -> (GyroEngine, FakeMotionSampler, FakeGyroMotionSink, ManualClock) {
        let sampler = FakeMotionSampler()
        let sink = FakeGyroMotionSink()
        let clock = ManualClock(start: 0)
        let engine = GyroEngine(sampler: sampler, sink: sink, clock: clock, observeAppLifecycle: false)
        return (engine, sampler, sink, clock)
    }

    @Test func forwardedDeltaCarriesGyroSourceAndNoFlagsWhileMoving() async {
        let (engine, sampler, sink, _) = makeEngine()
        await engine.start()
        engine.clutchPressBegan()
        #expect(await waitUntil { engine.state == .armed })

        var t: TimeInterval = 0
        sampler.deliver(makeSample(timestamp: t)) // bootstrap
        for _ in 0..<20 {
            t += 0.01
            sampler.deliver(makeSample(rotationRate: SIMD3(0, -1.0, 0), timestamp: t))
            await Task.yield()
        }

        #expect(await sink.waitForCount(1))
        let received = await sink.received
        let moved = received.first { $0.dx != 0 }
        #expect(moved != nil)
        #expect(moved?.source == .gyro)
        #expect(moved?.flags.isEmpty == true)
    }

    @Test func motionEndDatagramCarriesZeroDeltaAndMotionEndFlag() async {
        let (engine, _, sink, _) = makeEngine()
        await engine.start()
        engine.clutchPressBegan()
        #expect(await waitUntil { engine.state == .armed })
        engine.clutchPressEnded()

        #expect(await sink.waitForCount(1))
        let received = await sink.received
        #expect(received.last?.flags == [.motionEnd])
        #expect(received.last?.dx == 0)
        #expect(received.last?.dy == 0)
        #expect(received.last?.source == .gyro)
    }

    @Test func motionSuppressedImmediatelyAfterClickThenResumes() async {
        let (engine, sampler, sink, clock) = makeEngine()
        await engine.start()
        engine.clutchPressBegan()
        #expect(await waitUntil { engine.state == .armed })

        var t: TimeInterval = 0
        sampler.deliver(makeSample(timestamp: t)) // bootstrap

        clock.set(0)
        engine.suppressMotionAfterClick() // suppressed until clock reads 0.080

        for _ in 0..<10 {
            t += 0.01
            sampler.deliver(makeSample(rotationRate: SIMD3(0, -1.0, 0), timestamp: t))
            await Task.yield()
        }
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(engine.state == .armed)
        #expect(await sink.received.isEmpty)

        clock.set(0.2) // past the 80 ms suppression window
        for _ in 0..<10 {
            t += 0.01
            sampler.deliver(makeSample(rotationRate: SIMD3(0, -1.0, 0), timestamp: t))
            await Task.yield()
        }
        #expect(await sink.waitForCount(1))
        #expect(await waitUntil { engine.state == .moving })
    }
}
