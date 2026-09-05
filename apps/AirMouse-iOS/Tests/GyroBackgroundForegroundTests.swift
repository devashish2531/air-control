// Tests/GyroBackgroundForegroundTests.swift
// spec §4.3.1 (NFR-PERF-007): "Updates run only while the Air Mouse tab... is visible and the
// app is active; stopped otherwise." `GyroEngine` observes `UIApplication`'s background/foreground
// notifications directly (arch §3.2's "GyroEngine... stops updates when tab not visible").
import Foundation
import Testing
import UIKit
@testable import Air_Mouse

@MainActor
@Suite struct GyroBackgroundForegroundTests {
    private func makeEngine() -> (GyroEngine, FakeMotionSampler) {
        let sampler = FakeMotionSampler()
        let engine = GyroEngine(sampler: sampler, observeAppLifecycle: true)
        return (engine, sampler)
    }

    @Test func startingBeginsSampling() async {
        let (engine, sampler) = makeEngine()
        await engine.start()
        #expect(sampler.isActive)
        #expect(engine.isSampling)
    }

    @Test func stoppingEndsSampling() async {
        let (engine, sampler) = makeEngine()
        await engine.start()
        await engine.stop()
        #expect(!sampler.isActive)
        #expect(!engine.isSampling)
    }

    @Test func enteringBackgroundStopsSampling() async {
        let (engine, sampler) = makeEngine()
        await engine.start()
        #expect(sampler.isActive)

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        #expect(await waitUntil { !sampler.isActive })
    }

    @Test func returningToForegroundResumesSamplingWhenScreenStillVisible() async {
        let (engine, sampler) = makeEngine()
        await engine.start()
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        #expect(await waitUntil { !sampler.isActive })

        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        #expect(await waitUntil { sampler.isActive })
    }

    @Test func foregroundDoesNotResumeSamplingWhenScreenNotVisible() async {
        let (engine, sampler) = makeEngine()
        await engine.start()
        await engine.stop() // tab navigated away — screen no longer visible
        #expect(!sampler.isActive)

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(!sampler.isActive)
    }
}
