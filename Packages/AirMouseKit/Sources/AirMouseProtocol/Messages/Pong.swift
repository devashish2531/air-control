import Foundation

/// `pong` (H→C). spec §3.4.5: "`seq`, `t1` (echoed), `t2` int (host monotonic µs at receive), `t3`
/// int (host µs at send), `motion.clientTs` int? (timestamp field of the most recent accepted
/// motion datagram), `motion.hostTs` int? (host µs when it was received), `injectP50Us` int?
/// (host receive→post p50 over the last second)." spec §3.4.6: "RTT is `t4 − t1 − (t3 − t2)`."
public struct Pong: Codable, Sendable, Equatable {
    /// `motion.{clientTs,hostTs}`, present only when a motion datagram has been accepted this
    /// session.
    public struct MotionTiming: Codable, Sendable, Equatable {
        public var clientTs: Int64?
        public var hostTs: Int64?

        public init(clientTs: Int64? = nil, hostTs: Int64? = nil) {
            self.clientTs = clientTs
            self.hostTs = hostTs
        }
    }

    public var seq: Int
    public var t1: Int64
    public var t2: Int64
    public var t3: Int64
    public var motion: MotionTiming?
    public var injectP50Us: Int?

    public init(seq: Int, t1: Int64, t2: Int64, t3: Int64, motion: MotionTiming? = nil, injectP50Us: Int? = nil) {
        self.seq = seq
        self.t1 = t1
        self.t2 = t2
        self.t3 = t3
        self.motion = motion
        self.injectP50Us = injectP50Us
    }
}
