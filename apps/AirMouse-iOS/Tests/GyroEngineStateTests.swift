// Tests/GyroEngineStateTests.swift
// `GyroEngine`'s state machine (idle/armed/moving/calibrating) and delta forwarding, driven
// entirely through `FakeMotionSampler` so no real gyroscope is needed (spec §4.3).
import AirMouseFilters
import Foundation
import Testing
import simd
@testable import Air_Mouse

@MainActor
@Suite struct GyroEngineStateTests {
    private func makeEngine() -> (GyroEngine, FakeMotionSampler, FakeGyroMotionSink) {
        let sampler = FakeMotionSampler()
        let sink = FakeGyroMotionSink()
        let engine = GyroEngine(sampler: sampler, sink: sink, clock: ManualClock(), observeAppLifecycle: false)
        return (engine, sampler, sink)
    }

    @Test func startsIdle() {
        let (engine, _, _) = makeEngine()
        #expect(engine.state == .idle)
        #expect(engine.isGyroAvailable == true)
    }

    @Test func unavailableDeviceReportsFalse() {
        let sampler = FakeMotionSampler(isDeviceMotionAvailable: false)
        let engine = GyroEngine(sampler: sampler, observeAppLifecycle: false)
        #expect(engine.isGyroAvailable == false)
    }

    @Test func engagingClutchEntersArmed() async {
        let (engine, sampler, _) = makeEngine()
        await engine.start()
        #expect(sampler.startCallCount == 1)

        engine.clutchPressBegan()
        let armed = await waitUntil { engine.state == .armed }
        #expect(armed)
    }

    @Test func sustainedRotationProducesMovingAndForwardsDelta() async {
        let (engine, sampler, sink) = makeEngine()
        await engine.start()
        engine.clutchPressBegan()
        #expect(await waitUntil { engine.state == .armed })

        var t: TimeInterval = 0
        sampler.deliver(makeSample(timestamp: t)) // bootstrap sample: seeds filters, no delta
        for _ in 0..<20 {
            t += 0.01
            // A large, sustained rotation rate about the device's y-axis — with gravity along
            // -y (device upright, portrait) this is pure yaw, well above the 0.5°/s dead zone.
            sampler.deliver(makeSample(rotationRate: SIMD3(0, -1.0, 0), timestamp: t))
            await Task.yield()
        }

        #expect(await waitUntil { engine.state == .moving })
        #expect(await sink.waitForCount(1))
        let received = await sink.received
        #expect(received.contains { $0.dx != 0 && $0.source == .gyro })
    }

    @Test func stillnessWhileArmedStaysArmedNotMoving() async {
        let (engine, sampler, sink) = makeEngine()
        await engine.start()
        engine.clutchPressBegan()
        #expect(await waitUntil { engine.state == .armed })

        var t: TimeInterval = 0
        for _ in 0..<10 {
            t += 0.01
            sampler.deliver(makeSample(rotationRate: .zero, timestamp: t))
            await Task.yield()
        }
        await Task.yield()
        #expect(engine.state == .armed)
        let received = await sink.received
        #expect(received.isEmpty)
    }

    @Test func disengageReturnsToIdleAndSendsMotionEnd() async {
        let (engine, _, sink) = makeEngine()
        await engine.start()
        engine.clutchPressBegan()
        #expect(await waitUntil { engine.state == .armed })

        engine.clutchPressEnded() // hold mode default: release -> disengage
        #expect(await waitUntil { engine.state == .idle })
        #expect(await sink.waitForCount(1))
        let received = await sink.received
        #expect(received.last?.flags.contains(.motionEnd) == true)
        #expect(received.last?.dx == 0 && received.last?.dy == 0)
    }

    @Test func calibrationCompletesAfterHoldAndReturnsToIdle() async {
        let (engine, sampler, _) = makeEngine()
        await engine.start()
        engine.startCalibration()
        #expect(engine.state == .calibrating)
        #expect(engine.calibrationProgress == 0)

        var t: TimeInterval = 0
        for _ in 0..<105 {
            t += 0.01
            sampler.deliver(makeSample(rotationRate: .zero, timestamp: t))
            await Task.yield()
        }

        #expect(await waitUntil { engine.state != .calibrating })
        #expect(engine.state == .idle)
        #expect(engine.calibrationProgress == 1)
    }

    @Test func shakeDuringCalibrationRestartsHold() async {
        let (engine, sampler, _) = makeEngine()
        await engine.start()
        engine.startCalibration()

        var t: TimeInterval = 0
        for _ in 0..<60 { // 0.6 s of stillness
            t += 0.01
            sampler.deliver(makeSample(rotationRate: .zero, timestamp: t))
            await Task.yield()
        }
        #expect(await waitUntil { engine.calibrationProgress > 0.5 })

        t += 0.01
        // A shake: |ω| > 5°/s (~0.0873 rad/s) — well exceeded here.
        sampler.deliver(makeSample(rotationRate: SIMD3(0, 0, 2.0), timestamp: t))
        #expect(await waitUntil { engine.calibrationProgress < 0.2 })
        #expect(engine.state == .calibrating)
    }
}
