import Foundation

/// `heartbeat` (C→H). spec §3.4.5: "`seq` int, `t1` int (client monotonic µs)." spec §3.4.6:
/// "Client sends `heartbeat` every 500 ms from the moment `helloAck` arrives."
public struct Heartbeat: Codable, Sendable, Equatable {
    public var seq: Int
    /// Client monotonic clock, microseconds. `Int64` (not `Int`) because a µs monotonic clock
    /// exceeds `Int32.max` after ~35 minutes of uptime and the spec places no wrap on this field
    /// (unlike the motion payload's 32-bit `timestamp`, §3.5.2).
    public var t1: Int64

    public init(seq: Int, t1: Int64) {
        self.seq = seq
        self.t1 = t1
    }
}
