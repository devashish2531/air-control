// ActivityTrackingControlChannel — a thin `AirMouseCore.ControlChannel` decorator that records the
// last time any bytes arrived from the peer. Owned by the networking agent (assignment:
// "Services/SessionManager/").
//
// `AirMouseCore.HostSession.checkTimeouts(now:lastHeartbeatAt:)` needs its caller to track "when did
// a heartbeat last arrive" — but `HostSession` handles `heartbeat` control messages entirely inside
// its own private receive loop (replying with `pong`) and never surfaces that moment through its
// public `events` stream (spec §3.4.6's heartbeat is not one of `HostEvent`'s cases). Since the
// client sends a `heartbeat` every 500 ms regardless of what else it's doing (spec §3.4.6), "any
// bytes arrived on this control channel" is an accurate (if slightly more lenient — actual input
// activity counts too, which is the safe direction) proxy for "a heartbeat arrived", and this
// decorator is the only seam available to observe it without modifying `AirMouseCore` (CLAUDE.md:
// "only touch files inside the directories you were assigned").
import AirMouseCore
import AirMouseCrypto
import AirMouseFilters
import Foundation
import os

final class ActivityTrackingControlChannel: ControlChannel, @unchecked Sendable {
    private let wrapped: any ControlChannel
    private let lastActivityBox: OSAllocatedUnfairLock<TimeInterval>

    public nonisolated let incoming: AsyncThrowingStream<Data, any Error>

    init(wrapping wrapped: any ControlChannel, clock: any Clock) {
        self.wrapped = wrapped
        let box = OSAllocatedUnfairLock(initialState: clock.now())
        self.lastActivityBox = box
        self.incoming = AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chunk in wrapped.incoming {
                        box.withLock { $0 = clock.now() }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The clock time (same `Clock` instance passed to `init`, and to `HostSession`) at which bytes
    /// were last observed on `incoming` — a proxy for "a heartbeat last arrived at".
    func lastActivity() -> TimeInterval {
        lastActivityBox.withLock { $0 }
    }

    func send(_ frame: Data) async throws {
        try await wrapped.send(frame)
    }

    var peerFingerprint: Fingerprint? {
        get async { await wrapped.peerFingerprint }
    }

    func exporterSecret() async -> Data? {
        await wrapped.exporterSecret()
    }

    func close() async {
        await wrapped.close()
    }
}
