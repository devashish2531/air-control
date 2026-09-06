import Foundation

/// Byte 1 of the motion payload: which input generated this datagram. spec §3.5.2: "source |
/// 0 touch · 1 gyro · 2 external pointer (iPad trackpad/mouse) · 3 tcpFallback (set by host
/// bookkeeping only) · 255 probe". spec §3.7: "new sources use spare `source` values."
public enum MotionSource: UInt8, Sendable, Equatable, Hashable, CaseIterable {
    case touch = 0
    case gyro = 1
    case externalPointer = 2
    /// Set by the host, never sent by a client, to mark datagrams that actually arrived over the
    /// TCP fallback batch frame (§3.5.9) for diagnostics.
    case tcpFallback = 3
    /// A latency probe (§3.5.8), not a motion sample; `samples` is 0 and all deltas are 0.
    case probe = 255
}
