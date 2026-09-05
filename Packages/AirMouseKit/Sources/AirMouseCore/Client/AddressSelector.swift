import Foundation

/// Orders candidate host addresses for a connect attempt (spec §3.3.2): "Candidate order:
/// (1) the endpoint of the current Bonjour result for this `hostID` (if browsing),
/// (2) `lastKnownAddresses` newest first, (3) `qrAddresses` in QR order." Also enforces spec
/// §4.5.4 / FR-CR-011: "Non-private addresses are refused unless from a QR scan."
///
/// A pure value type/namespace — no networking, no timers (arch §3.1). The actual staggered
/// happy-eyeballs connect loop (700 ms stagger, 4 s per-candidate, 12 s overall) is timing/`Network`
/// behavior the apps' `ConnectionManager` drives; this type only produces the ordered list.
public enum AddressSelector: Sendable {
    /// Where one candidate address came from — determines whether the private-range guard applies.
    public enum Source: Sendable, Equatable, Hashable {
        case bonjour
        case lastKnown
        case qr
    }

    /// One candidate endpoint to try, in the order returned by `order(bonjour:lastKnown:qr:)`.
    public struct Candidate: Sendable, Equatable, Hashable {
        /// An IPv4/IPv6 literal (no brackets, no zone — matching `AirMouseProtocol.IPLiteral`).
        public var address: String
        public var port: Int
        public var source: Source
        /// `true` for an IPv6 literal (contains `:`); used to test IPv6-preference ordering
        /// within a single source's own list, which is the caller's responsibility to supply
        /// pre-ordered per spec §3.1.3 ("hotspot/bridge → Wi-Fi → Ethernet → link-local IPv6
        /// last") — `AddressSelector` does not reorder within a source, only concatenates and
        /// filters across sources.
        public var isIPv6: Bool { address.contains(":") }

        public init(address: String, port: Int, source: Source) {
            self.address = address
            self.port = port
            self.source = source
        }
    }

    /// Produces the final, deduplicated, filtered candidate order for one connect attempt.
    ///
    /// - Parameters:
    ///   - bonjour: the current Bonjour result's endpoint, if browsing and one is known.
    ///   - lastKnown: `lastKnownAddresses`, already newest-first (spec §3.2.4: "≤ 6, with
    ///     timestamps"; ordering by recency is the caller's `TrustedHostRecord` responsibility).
    ///   - qr: `qrAddresses`, already in QR order.
    public static func order(
        bonjour: Candidate?,
        lastKnown: [Candidate],
        qr: [Candidate]
    ) -> [Candidate] {
        var seen = Set<String>()
        var result: [Candidate] = []
        for candidate in ([bonjour].compactMap { $0 }) + lastKnown + qr {
            guard isAllowed(candidate) else { continue }
            let key = "\(candidate.address)#\(candidate.port)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(candidate)
        }
        return result
    }

    /// spec §4.5.4 / FR-CR-011: "Non-private addresses are refused unless from a QR scan."
    public static func isAllowed(_ candidate: Candidate) -> Bool {
        candidate.source == .qr || isPrivateAddress(candidate.address)
    }

    /// spec §3.3.2: "not RFC 1918, not `fe80::/10`, `fc00::/7`, `169.254/16`, `172.20.10/28`" are
    /// the ranges that get skipped unless from a QR — i.e. everything *in* those ranges (plus
    /// loopback, included for local testing/CLI use) counts as private/allowed.
    public static func isPrivateAddress(_ address: String) -> Bool {
        address.contains(":") ? isPrivateIPv6(address) : isPrivateIPv4(address)
    }

    private static func isPrivateIPv4(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return false }
        let (a, b) = (parts[0], parts[1])
        if a == 10 { return true } // 10.0.0.0/8
        if a == 172, (16...31).contains(b) { return true } // 172.16.0.0/12 (incl. 172.20.10/28 hotspot)
        if a == 192, b == 168 { return true } // 192.168.0.0/16
        if a == 169, b == 254 { return true } // 169.254.0.0/16 (link-local)
        if a == 127 { return true } // loopback, for local dev/CLI
        return false
    }

    private static func isPrivateIPv6(_ address: String) -> Bool {
        let lowered = address.lowercased()
        if lowered == "::1" { return true } // loopback
        if lowered.hasPrefix("fe8") || lowered.hasPrefix("fe9")
            || lowered.hasPrefix("fea") || lowered.hasPrefix("feb") {
            return true // fe80::/10 (link-local): first hextet 0xfe80...0xfebf
        }
        // fc00::/7 spans first byte 0xfc-0xfd, i.e. first hextet "fc00"-"fdff".
        if let firstGroup = lowered.split(separator: ":", omittingEmptySubsequences: false).first,
           let value = UInt16(firstGroup, radix: 16) {
            let topByte = UInt8(value >> 8)
            if topByte == 0xFC || topByte == 0xFD { return true }
        }
        return false
    }
}
