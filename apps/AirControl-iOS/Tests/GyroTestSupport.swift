// Tests/GyroTestSupport.swift
// Fakes shared by the Gyro*.swift test files: a scriptable `MotionSampling` conformance (so tests
// never need a real gyroscope / run identically in the simulator) and a recording
// `MotionEnqueuing` sink (the Motion agent's protocol — see `GyroEngine.swift`'s doc comment for
// why this module calls it directly rather than defining its own).
import AirControlProtocol
import Foundation
import simd
@testable import Air_Control

/// A `MotionSampling` conformance driven entirely by the test: `deliver(_:)` synchronously invokes
/// whatever handler `startUpdates` was given, on the calling thread (tests don't need a real
/// background queue — `GyroEngine` only requires *a* queue is passed to CoreMotion's real API).
final class FakeMotionSampler: MotionSampling {
    var isDeviceMotionAvailable: Bool
    private(set) var isActive: Bool = false
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lastInterval: TimeInterval?
    private var handler: (@Sendable (MotionSampleData) -> Void)?

    init(isDeviceMotionAvailable: Bool = true) {
        self.isDeviceMotionAvailable = isDeviceMotionAvailable
    }

    func startUpdates(interval: TimeInterval, queue: OperationQueue, handler: @escaping @Sendable (MotionSampleData) -> Void) {
        startCallCount += 1
        isActive = true
        lastInterval = interval
        self.handler = handler
    }

    func stopUpdates() {
        stopCallCount += 1
        isActive = false
        handler = nil
    }

    /// Delivers one sample as if CoreMotion had produced it. No-ops if not currently "started"
    /// (mirrors CoreMotion never calling a stopped manager's handler).
    func deliver(_ sample: MotionSampleData) {
        handler?(sample)
    }
}

/// Records every delta `GyroEngine` forwards, for assertions on dx/dy/flags/source/timestamp.
actor FakeGyroMotionSink: MotionEnqueuing {
    struct Recorded: Sendable, Equatable {
        var dx: Double
        var dy: Double
        var flags: MotionFlags
        var source: MotionSource
        var timestamp: TimeInterval
    }

    private(set) var received: [Recorded] = []
    private(set) var scrollReceived: [Recorded] = []

    func enqueue(dx: Double, dy: Double, flags: MotionFlags, source: MotionSource, timestamp: TimeInterval) {
        received.append(Recorded(dx: dx, dy: dy, flags: flags, source: source, timestamp: timestamp))
    }

    func enqueueScroll(dx: Double, dy: Double, flags: MotionFlags, source: MotionSource, timestamp: TimeInterval) {
        scrollReceived.append(Recorded(dx: dx, dy: dy, flags: flags, source: source, timestamp: timestamp))
    }

    func waitForCount(_ count: Int, timeout: TimeInterval = 2.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while received.count < count, Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return received.count >= count
    }
}

/// Polls `predicate` on the main actor until it's true or `timeout` elapses — `GyroEngine` hops
/// through the `GyroProcessor` actor asynchronously, so state updates aren't visible synchronously
/// right after `sampler.deliver(_:)`.
@MainActor
func waitUntil(timeout: TimeInterval = 2.0, _ predicate: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !predicate(), Date() < deadline {
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return predicate()
}

/// Builds a still, upright-portrait `MotionSampleData` sample; individual tests override the
/// fields they're exercising.
func makeSample(
    rotationRate: SIMD3<Double> = .zero,
    gravity: SIMD3<Double> = SIMD3(0, -1, 0),
    userAcceleration: SIMD3<Double> = .zero,
    attitudeAvailable: Bool = true,
    magneticFieldAccuracy: MagneticFieldCalibrationAccuracy = .high,
    timestamp: TimeInterval
) -> MotionSampleData {
    MotionSampleData(
        rotationRate: rotationRate,
        gravity: gravity,
        userAcceleration: userAcceleration,
        attitudeAvailable: attitudeAvailable,
        magneticFieldAccuracy: magneticFieldAccuracy,
        timestamp: timestamp
    )
}
