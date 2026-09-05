// Services/MotionPublisher/MotionPublisher.swift
// `MotionPublisher` actor (arch §3.2: "executor = DispatchSerialQueue 'motion' .userInteractive").
// Owns the coalescing accumulator, the 120 Hz rate cap, fixed-point quantization with saturation,
// and a bounded drop-oldest ready queue, per spec §3.5.7 ("Coalescing rules (client)") and this
// agent's assignment. Hands finished `MotionPayload`s to a `MotionDatagramSink` — sealing them
// into the 44-byte AEAD datagram (or batching into a TCP-fallback frame) is out of scope here
// (CLAUDE.md: "AirMouseCore never imports Network"; only the Connection agent's session type
// touches the wire beyond this plaintext payload).
//
// Deviation from the spec's literal "in-flight cap 2, tracked by send completions" (§3.5.7):
// `MotionDatagramSink.sendMotion(_:)` is a synchronous, fire-and-forget call by this agent's
// assignment (no completion signal crosses this boundary — the actual socket-level backpressure
// lives in the Connection agent's `NWConnection`, which this module never touches). In its place
// this actor enforces (a) a strict 120 Hz send-rate cap measured in the same clock domain as the
// caller-supplied sample timestamps (so it needs no injected wall clock on the hot path), and
// (b) a bounded (`ProtocolConstants.motionInFlightDatagramCap`, i.e. 2) ready-to-send queue that
// drops the OLDEST queued-but-unsent payload (incrementing `droppedDatagramCount`) rather than
// growing unboundedly, if payloads are produced faster than they can be handed to the sink.
// Under normal operation (a synchronous sink) this queue drains immediately every flush and the
// drop path never fires; it exists as the defensive backpressure valve the assignment asks for.
//
// Deviation, diagnostics: `DiagnosticsModel`'s `LatencySample` (Features/Diagnostics, owned by
// another agent, not edited here) has no "samples/s" / "coalesced count" fields. This actor feeds
// what `LatencySample` does have (`inFlightDatagrams`) through the existing `DiagnosticsReceiving`
// protocol every 250 ms, and additionally exposes the richer `MotionPublisherStats` (samples/s,
// coalesced count, dropped/sent/queued counts) via a `nonisolated` accessor for anything that
// wants it directly (this agent's own tests included) until `LatencySample` grows those fields.

import Foundation
import os
import AirMouseFilters
import AirMouseProtocol

public actor MotionPublisher: MotionEnqueuing {
    private let serialQueue = DispatchSerialQueue(label: "com.airmouse.app.motion", qos: .userInteractive)

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        serialQueue.asUnownedSerialExecutor()
    }

    /// Minimum interval between flushed datagrams: spec's "Rate cap 120 Hz" — never send faster
    /// than one datagram per display frame at 120 Hz (≈ 8.33 ms), measured against the caller's
    /// own sample timestamps rather than a wall clock.
    public static let minSendInterval: TimeInterval = 1.0 / 120.0

    private struct Accumulator {
        var dx: Double = 0
        var dy: Double = 0
        var scrollX: Double = 0
        var scrollY: Double = 0
        var flags: MotionFlags = []
        var samples: Int = 0
        var source: MotionSource = .touch
        var lastTimestamp: TimeInterval = 0
    }

    /// spec §3.5.2/§3.5.6: these flags must ride on a datagram even with zero deltas — the
    /// coalescing rule that "zero-delta frames are not sent" does not apply to them, and they
    /// bypass the 120 Hz rate cap (they are discrete, rare, gesture-boundary events, not a
    /// continuous stream) so the host sees the boundary promptly.
    private static let mandatoryFlags: MotionFlags = [.scrollBegan, .scrollEnded, .motionEnd, .probe]

    private let sink: any MotionDatagramSink
    private weak var diagnostics: (any DiagnosticsReceiving)?

    private var pending: Accumulator?
    private var lastFlushTimestamp: TimeInterval = -.infinity
    private var readyQueue: DropOldestQueue<MotionPayload>

    private var sentDatagramCount = 0
    private var samplesSinceLastDiagnosticsTick = 0
    private var lastDiagnosticsTickTime: TimeInterval = 0

    private var diagnosticsTimer: DispatchSourceTimer?
    private let isPublishingBox = OSAllocatedUnfairLock(initialState: false)
    private let statsBox: OSAllocatedUnfairLock<MotionPublisherStats>

    public init(sink: any MotionDatagramSink, diagnostics: (any DiagnosticsReceiving)? = nil) {
        self.sink = sink
        self.diagnostics = diagnostics
        self.statsBox = OSAllocatedUnfairLock(initialState: MotionPublisherStats())
        self.readyQueue = DropOldestQueue(capacity: ProtocolConstants.motionInFlightDatagramCap)
        // A synchronous actor `init` runs in a nonisolated context (no executor is guaranteed yet),
        // so it cannot call other actor-isolated methods directly; hop onto the actor once it's
        // fully initialized to start the (off-hot-path) diagnostics timer.
        Task { [weak self] in await self?.startDiagnosticsTimer() }
    }

    deinit {
        diagnosticsTimer?.cancel()
    }

    // MARK: Status (read from any isolation domain, incl. the shell's `MotionPublishing`)

    /// Whether at least one motion sample has been enqueued. `nonisolated` (lock-backed) rather
    /// than an ordinary actor-isolated property because an `actor` cannot itself conform to
    /// `MotionPublishing` (App/ServiceProtocols.swift) — that protocol is `@MainActor`-isolated,
    /// and Swift does not allow an actor type to conform to a global-actor-isolated protocol at
    /// all, even via `nonisolated` members. `MotionPublisherStatusAdapter` (this directory) is a
    /// tiny `@MainActor` facade that reads this property and is the thing actually plugged into
    /// `AppEnvironment.motion`.
    public nonisolated var isPublishing: Bool {
        isPublishingBox.withLock { $0 }
    }

    /// Snapshot of the richer counters (see this file's deviation note); safe to read from any
    /// isolation domain.
    public nonisolated var stats: MotionPublisherStats {
        statsBox.withLock { $0 }
    }

    // MARK: MotionEnqueuing

    public func enqueue(dx: Double, dy: Double, flags: MotionFlags, source: MotionSource, timestamp: TimeInterval) {
        merge(dx: dx, dy: dy, scrollX: 0, scrollY: 0, flags: flags, source: source, timestamp: timestamp)
    }

    public func enqueueScroll(dx: Double, dy: Double, flags: MotionFlags, source: MotionSource, timestamp: TimeInterval) {
        merge(dx: 0, dy: 0, scrollX: dx, scrollY: dy, flags: flags, source: source, timestamp: timestamp)
    }

    // MARK: Hot path

    private func merge(
        dx: Double, dy: Double, scrollX: Double, scrollY: Double,
        flags: MotionFlags, source: MotionSource, timestamp: TimeInterval
    ) {
        isPublishingBox.withLock { $0 = true }
        samplesSinceLastDiagnosticsTick += 1

        var acc = pending ?? Accumulator()
        acc.dx += dx
        acc.dy += dy
        acc.scrollX += scrollX
        acc.scrollY += scrollY
        acc.flags.formUnion(flags)
        acc.samples += 1
        acc.source = source
        acc.lastTimestamp = timestamp
        pending = acc

        let isMandatory = !flags.intersection(Self.mandatoryFlags).isEmpty
        let elapsedSinceFlush = timestamp - lastFlushTimestamp
        guard isMandatory || elapsedSinceFlush >= Self.minSendInterval else { return }
        flush(now: timestamp)
    }

    private func flush(now: TimeInterval) {
        guard let acc = pending else { return }
        let hasMandatoryFlag = !acc.flags.intersection(Self.mandatoryFlags).isEmpty
        let hasDelta = acc.dx != 0 || acc.dy != 0 || acc.scrollX != 0 || acc.scrollY != 0
        // spec §3.5.7: "Zero-delta frames are not sent, except one final datagram with
        // `motionEnd` on lift/release, and `scrollBegan`/`scrollEnded` flags always ride on a
        // datagram (zero deltas allowed)."
        guard hasDelta || hasMandatoryFlag else {
            pending = nil
            return
        }

        let payload = MotionPayload(
            flags: acc.flags,
            source: acc.source,
            samples: UInt8(clamping: max(acc.samples, 1)),
            timestamp: TimestampMicros.encode(acc.lastTimestamp),
            dxPoints: acc.dx,
            dyPoints: acc.dy,
            scrollXPoints: acc.scrollX,
            scrollYPoints: acc.scrollY
        )
        pending = nil
        lastFlushTimestamp = now
        enqueueReady(payload)
    }

    private func enqueueReady(_ payload: MotionPayload) {
        readyQueue.append(payload)
        drain()
    }

    private func drain() {
        for payload in readyQueue.drainAll() {
            sink.sendMotion(payload)
            sentDatagramCount += 1
        }
    }

    // MARK: Diagnostics (spec §8.2 / arch §8, off the hot path — 4 Hz per architecture's stated
    // Diagnostics window sampling rate)

    private func startDiagnosticsTimer() {
        let timer = DispatchSource.makeTimerSource(queue: serialQueue)
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250), leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            self?.assumeIsolated { publisher in
                publisher.reportDiagnostics()
            }
        }
        timer.resume()
        diagnosticsTimer = timer
    }

    private func reportDiagnostics() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastDiagnosticsTickTime
        let samplesPerSecond = (lastDiagnosticsTickTime > 0 && elapsed > 0)
            ? Double(samplesSinceLastDiagnosticsTick) / elapsed
            : 0
        samplesSinceLastDiagnosticsTick = 0
        lastDiagnosticsTickTime = now

        let snapshot = MotionPublisherStats(
            samplesPerSecond: samplesPerSecond,
            coalescedCount: pending?.samples ?? 0,
            droppedDatagramCount: readyQueue.droppedCount,
            sentDatagramCount: sentDatagramCount,
            queuedDatagramCount: readyQueue.count
        )
        statsBox.withLock { $0 = snapshot }

        guard let diagnostics else { return }
        let inFlight = readyQueue.count
        // `DiagnosticsReceiving` is `@MainActor`-isolated but not declared `Sendable` (it lives in
        // Features/Diagnostics, owned by another agent, not edited here), so it cannot be
        // captured directly in this `@Sendable` `Task` closure. The reference is only ever
        // touched under `@MainActor` on the other side of this hop — the box below only carries
        // it across, never accesses it here — so `@unchecked Sendable` is safe.
        let box = UncheckedSendableBox(value: diagnostics)
        Task { @MainActor in
            box.value.ingest(LatencySample(channel: .udp, inFlightDatagrams: inFlight))
        }
    }
}

/// See `reportDiagnostics()`'s comment: a minimal escape hatch for handing a `@MainActor`-isolated
/// (but not `Sendable`-declared) reference across one `Task` boundary without touching it here.
private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
}
