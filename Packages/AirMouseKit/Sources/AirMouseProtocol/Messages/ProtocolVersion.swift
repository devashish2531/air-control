import Foundation

/// The protocol's major version and the negotiation rule of spec §3.4.4: "the host picks
/// `max(clientMin, hostMin) … min(clientMax, hostMax)` → highest common; if empty →
/// `error protocol.versionMismatch`". spec §3.0: "Protocol version | `1` (integer). Independent of
/// app semantic versions (NFR-OSS-007)."
public struct ProtocolVersion: Sendable, Equatable, Hashable, Comparable, RawRepresentable {
    public var rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(_ value: Int) {
        self.rawValue = value
    }

    /// The version this build of the package implements. spec §3.0.
    public static let current = ProtocolVersion(ProtocolConstants.protocolVersion)

    public static func < (lhs: ProtocolVersion, rhs: ProtocolVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Negotiates the highest protocol version both sides support, per spec §3.4.4.
    ///
    /// - Returns: `max(clientMin, hostMin) ... min(clientMax, hostMax)`'s upper bound, i.e. the
    ///   highest common version, or `nil` if the ranges do not overlap (caller should send
    ///   `error protocol.versionMismatch` and close, per spec §3.4.4 and §3.2.6).
    public static func negotiate(clientMin: Int, clientMax: Int, hostMin: Int, hostMax: Int) -> ProtocolVersion? {
        let lowerBound = Swift.max(clientMin, hostMin)
        let upperBound = Swift.min(clientMax, hostMax)
        guard lowerBound <= upperBound else { return nil }
        return ProtocolVersion(upperBound)
    }
}
