// Tests/GyroCalibrationTests.swift
// Calibration progress (spec §4.3.7: 1 s hold, restarts on a shaky hold) and its effect on the
// bias-corrected dead zone (spec §4.3.5 / AM-GY-04: "phone on a table → 0 px creep").
import Foundation
import Testing
import simd
@testable import Air_Mouse

@MainActor
@Suite struct GyroCalibrationTests {
    private func makeEngine() -> (GyroEngine, FakeMotionSampler, FakeGyroMotionSink) {
        let sampler = FakeMotionSampler()
        let sink = FakeGyroMotionSink()
        let engine = GyroEngine(sampler: sampler, sink: sink, observeAppLifecycle: false)
        return (engine, sampler, sink)
    }

    @Test func progressRisesMonotonicallyToOneOverTheHold() async {
        let (engine, sampler, _) = makeEngine()
        await engine.start()
        engine.startCalibration()

        var lastProgress = 0.0
        var t: TimeInterval = 0
        for _ in 0..<105 {
            t += 0.01
            sampler.deliver(makeSample(rotationRate: .zero, timestamp: t))
            #expect(await waitUntil(timeout: 1) { engine.calibrationProgress >= lastProgress })
            lastProgress = engine.calibrationProgress
        }

        #expect(await waitUntil { engine.state == .idle })
        #expect(engine.calibrationProgress == 1)
    }

    @Test func cancelingMidHoldReturnsToIdleWithoutCompleting() async {
        let (engine, sampler, _) = makeEngine()
        await engine.start()
        engine.startCalibration()

        var t: TimeInterval = 0
        for _ in 0..<30 { // 0.3 s in — well short of the 1 s hold
            t += 0.01
            sampler.deliver(makeSample(rotationRate: .zero, timestamp: t))
            await Task.yield()
        }
        #expect(await waitUntil { engine.calibrationProgress > 0 })

        engine.cancelCalibration()
        #expect(await waitUntil { engine.state == .idle })
        #expect(engine.calibrationProgress == 0)
    }

    @Test func onCalibrationCompletedFiresExactlyOnce() async {
        let (engine, sampler, _) = makeEngine()
        var completions = 0
        engine.onCalibrationCompleted = { completions += 1 }
        await engine.start()
        engine.startCalibration()

        var t: TimeInterval = 0
        for _ in 0..<120 { // well past the 1 s hold
            t += 0.01
            sampler.deliver(makeSample(rotationRate: .zero, timestamp: t))
            await Task.yield()
        }
        #expect(await waitUntil { engine.state == .idle })
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(completions == 1)
    }

    /// AM-GY-04 (research doc): "auto-freeze when accelerometer variance says the phone is at
    /// rest" / spec §4.3.5's dead zone — sub-threshold noise while genuinely still must never
    /// register as cursor movement, calibrated or not.
    @Test func subDeadZoneNoiseNeverProducesMotionAfterCalibration() async {
        let (engine, sampler, sink) = makeEngine()
        await engine.start()
        engine.startCalibration()

        var t: TimeInterval = 0
        for _ in 0..<105 {
            t += 0.01
            sampler.deliver(makeSample(rotationRate: .zero, timestamp: t))
            await Task.yield()
        }
        #expect(await waitUntil { engine.state == .idle })

        engine.clutchPressBegan()
        #expect(await waitUntil { engine.state == .armed })

        // ~0.2°/s (~0.0035 rad/s), comfortably under the 0.5°/s default dead zone.
        let tinyNoise = SIMD3<Double>(0, -0.0035, 0)
        for _ in 0..<50 {
            t += 0.01
            sampler.deliver(makeSample(rotationRate: tinyNoise, timestamp: t))
            await Task.yield()
        }
        try? await Task.sleep(nanoseconds: 30_000_000)

        #expect(engine.state == .armed) // never promoted to .moving
        let received = await sink.received
        #expect(received.isEmpty)
    }
}
