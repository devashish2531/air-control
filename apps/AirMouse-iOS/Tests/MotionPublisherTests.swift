// Tests/MotionPublisherTests.swift
// `MotionPublisher` coalescing, 120 Hz rate cap, and fixed-point saturation (this agent's
// assignment: "MotionPublisher coalescing/rate cap/saturation with a manual clock" — driven here
// by explicit `timestamp:` arguments to `enqueue`/`enqueueScroll` rather than a wall clock, since
// that is the clock domain the actor's rate cap actually measures against; see
// `MotionPublisher.swift`'s doc comment). Actor calls are `await`ed directly, so every assertion
// after an `await publisher.enqueue(...)` observes a fully-settled state — no sleeping/polling.

import Testing
import Foundation
import AirMouseProtocol
@testable import Air_Mouse

private final class RecordingMotionDatagramSink: MotionDatagramSink, @unchecked Sendable {
    private let lock = NSLock()
    private var _payloads: [MotionPayload] = []

    var payloads: [MotionPayload] {
        lock.lock(); defer { lock.unlock() }
        return _payloads
    }

    func sendMotion(_ payload: MotionPayload) {
        lock.lock(); defer { lock.unlock() }
        _payloads.append(payload)
    }
}

@Suite struct MotionPublisherTests {
    private func makePublisher() -> (MotionPublisher, RecordingMotionDatagramSink) {
        let sink = RecordingMotionDatagramSink()
        let publisher = MotionPublisher(sink: sink)
        return (publisher, sink)
    }

    @Test func firstEnqueueFlushesImmediately() async {
        let (publisher, sink) = makePublisher()
        await publisher.enqueue(dx: 3, dy: 4, flags: [], source: .touch, timestamp: 0)

        #expect(sink.payloads.count == 1)
        #expect(sink.payloads[0].dxPoints == 3)
        #expect(sink.payloads[0].dyPoints == 4)
        #expect(sink.payloads[0].samples == 1)
        #expect(sink.payloads[0].source == .touch)
    }

    @Test func zeroDeltaWithoutMandatoryFlagIsNotSent() async {
        let (publisher, sink) = makePublisher()
        await publisher.enqueue(dx: 0, dy: 0, flags: [], source: .touch, timestamp: 0)
        #expect(sink.payloads.isEmpty)
    }

    @Test func rapidEnqueuesWithinRateCapWindowCoalesceIntoOneDatagram() async {
        let (publisher, sink) = makePublisher()
        await publisher.enqueue(dx: 1, dy: 0, flags: [], source: .touch, timestamp: 0.0) // first: flushes immediately
        await publisher.enqueue(dx: 2, dy: 0, flags: [], source: .touch, timestamp: 0.001) // within 8.33 ms: coalesces
        await publisher.enqueue(dx: 3, dy: 0, flags: [], source: .touch, timestamp: 0.002) // still within window: coalesces

        #expect(sink.payloads.count == 1)
        #expect(sink.payloads[0].dxPoints == 1)

        // Past the rate-cap window since the last flush: the coalesced remainder goes out now.
        await publisher.enqueue(dx: 4, dy: 0, flags: [], source: .touch, timestamp: 0.01)

        #expect(sink.payloads.count == 2)
        #expect(sink.payloads[1].dxPoints == 9) // 2 + 3 + 4
        #expect(sink.payloads[1].samples == 3)
    }

    @Test func mandatoryFlagsBypassTheRateCap() async {
        let (publisher, sink) = makePublisher()
        await publisher.enqueue(dx: 1, dy: 0, flags: [], source: .touch, timestamp: 0.0)
        #expect(sink.payloads.count == 1)

        // Well within the 8.33 ms window, but `scrollBegan` must still ride out immediately
        // (spec §3.5.7: "scrollBegan/scrollEnded flags always ride on a datagram").
        await publisher.enqueueScroll(dx: 0, dy: 0, flags: [.scrollBegan], source: .touch, timestamp: 0.001)

        #expect(sink.payloads.count == 2)
        #expect(sink.payloads[1].flags.contains(.scrollBegan))
    }

    @Test func motionEndSendsEvenWithZeroDelta() async {
        let (publisher, sink) = makePublisher()
        await publisher.enqueue(dx: 0, dy: 0, flags: [.motionEnd], source: .touch, timestamp: 0)
        #expect(sink.payloads.count == 1)
        #expect(sink.payloads[0].flags.contains(.motionEnd))
        #expect(sink.payloads[0].dxPoints == 0)
    }

    @Test func extremeDeltaSaturatesRatherThanWrapping() async {
        let (publisher, sink) = makePublisher()
        await publisher.enqueue(dx: 100_000, dy: -100_000, flags: [], source: .touch, timestamp: 0)

        #expect(sink.payloads.count == 1)
        #expect(sink.payloads[0].dx == Int16.max)
        #expect(sink.payloads[0].dy == Int16.min)
    }

    @Test func scrollDeltasSaturateIndependentlyOfMotionDeltas() async {
        let (publisher, sink) = makePublisher()
        await publisher.enqueueScroll(dx: -100_000, dy: 100_000, flags: [], source: .touch, timestamp: 0)

        #expect(sink.payloads[0].scrollX == Int16.min)
        #expect(sink.payloads[0].scrollY == Int16.max)
        #expect(sink.payloads[0].dx == 0)
        #expect(sink.payloads[0].dy == 0)
    }

    @Test func synthetic120HzStreamCapsAtOnePayloadPerRateCapInterval() async {
        let (publisher, sink) = makePublisher()
        let sampleCount = 120
        // A hair over exactly `minSendInterval` apart (not exactly equal) so each step's elapsed
        // time is unambiguously >= the rate-cap threshold regardless of floating-point rounding —
        // a ~0.1 ms cumulative drift over the whole second, negligible for "roughly 120 Hz".
        let step = MotionPublisher.minSendInterval * 1.0001
        for i in 0..<sampleCount {
            await publisher.enqueue(dx: 1, dy: 0, flags: [], source: .touch, timestamp: TimeInterval(i) * step)
        }
        #expect(sink.payloads.count <= 120)
        // No data lost to the rate cap — every raw sample is accounted for across the datagrams.
        #expect(sink.payloads.reduce(0) { $0 + Int($1.samples) } == sampleCount)
    }

    @Test func synthetic240HzStreamIsCoalescedDownToAtMost120PayloadsPerSecond() async {
        let (publisher, sink) = makePublisher()
        let sampleCount = 240
        for i in 0..<sampleCount {
            let timestamp = TimeInterval(i) / 240.0 // a 240 Hz input stream, twice the rate cap
            await publisher.enqueue(dx: 1, dy: 0, flags: [], source: .touch, timestamp: timestamp)
        }
        #expect(sink.payloads.count <= 120)
        // A handful of trailing samples can still be sitting in the pending accumulator, waiting
        // for the next rate-cap tick (or a mandatory flag) to flush them out — nothing is ever
        // dropped by the rate cap itself, only coalesced or, at the very end of a burst, briefly
        // deferred. The exact remainder depends on where floating-point timestamp rounding lands
        // relative to the rate-cap boundary (observed: 2 of 240 samples still pending at the
        // end), so this allows a small bounded margin rather than an exact count.
        let flushedSamples = sink.payloads.reduce(0) { $0 + Int($1.samples) }
        #expect(flushedSamples >= sampleCount - 4)
        #expect(flushedSamples <= sampleCount)
    }

    @Test func isPublishingBecomesTrueAfterFirstEnqueue() async {
        let (publisher, _) = makePublisher()
        #expect(publisher.isPublishing == false)
        await publisher.enqueue(dx: 1, dy: 1, flags: [], source: .touch, timestamp: 0)
        #expect(publisher.isPublishing == true)
    }
}

@Suite struct DropOldestQueueTests {
    @Test func appendPastCapacityDropsTheOldestAndCounts() {
        var queue = DropOldestQueue<Int>(capacity: 2)
        queue.append(1)
        queue.append(2)
        queue.append(3)

        #expect(queue.count == 2)
        #expect(queue.droppedCount == 1)
        #expect(queue.elements == [2, 3])
    }

    @Test func drainAllEmptiesTheQueueAndReturnsOldestFirst() {
        var queue = DropOldestQueue<Int>(capacity: 3)
        queue.append(1)
        queue.append(2)
        let drained = queue.drainAll()

        #expect(drained == [1, 2])
        #expect(queue.isEmpty)
    }
}
