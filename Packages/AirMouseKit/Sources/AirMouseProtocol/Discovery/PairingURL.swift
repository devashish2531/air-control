import Foundation

/// The QR/manual-fallback pairing payload. spec §3.1.3:
/// ```
/// airmouse://pair?v=1&id=<hostID>&n=<name>&a=<addr1,addr2,…>&p=<tcpPort>&u=<udpPort>&fp=<certFP>&s=<secret>
/// ```
///
/// | Param | Required | Encoding | Size | Semantics |
/// |---|---|---|---|---|
/// | `v` | yes | decimal | 1–3 chars | Protocol major version the QR format belongs to |
/// | `id` | yes | b64u of 16 bytes | 22 | Host ID |
/// | `n` | yes | percent-encoded UTF-8 | ≤ 63 bytes decoded | Host display name |
/// | `a` | yes | comma-separated literal IPv4/IPv6 (no brackets, no zone) | 1–6 addresses | Ordered candidate list |
/// | `p` | yes | decimal | ≤ 5 | TCP port |
/// | `u` | no | decimal | ≤ 5 | UDP port; default = `p` |
/// | `fp` | yes | b64u of 32 bytes | 43 | Full host certificate fingerprint |
/// | `s` | yes | b64u of 16 bytes | 22 | One-time pairing secret |
///
/// "Total URL length SHALL be ≤ 512 bytes ...; the host truncates the address list, not the
/// secret, to stay within the limit. A URL with missing/malformed required params → E-PAIR-URL."
public struct PairingURL: Sendable, Equatable {
    public static let scheme = "airmouse"
    public static let pairHost = "pair"
    /// spec §3.1.3 / §11.3: 512 bytes.
    public static let maxURLLength = ProtocolConstants.qrURLMaxBytes
    /// spec §3.1.3 / §11.3: 1–6 addresses.
    public static let maxAddresses = ProtocolConstants.qrMaxAddresses

    public var version: Int
    public var hostID: Data
    public var hostName: String
    /// 1–6 addresses, in the spec's preference order: "hotspot/bridge → Wi-Fi → Ethernet →
    /// link-local IPv6 last" (spec §3.1.3) — this type does not reorder or classify them, it only
    /// validates that each is a syntactically-valid IPv4/IPv6 literal (`IPLiteral`); the caller
    /// supplies them in the order it wants tried (spec §3.3.2).
    public var addresses: [String]
    public var tcpPort: Int
    public var udpPort: Int
    public var fingerprint: Data
    public var secret: Data

    /// Constructs and validates a pairing URL from already-typed fields.
    ///
    /// - Parameter udpPort: defaults to `tcpPort` per spec §3.1.3 ("`u` ... default = `p`").
    public init(
        version: Int,
        hostID: Data,
        hostName: String,
        addresses: [String],
        tcpPort: Int,
        udpPort: Int? = nil,
        fingerprint: Data,
        secret: Data
    ) throws {
        self.version = version
        self.hostID = hostID
        self.hostName = hostName
        self.addresses = addresses
        self.tcpPort = tcpPort
        self.udpPort = udpPort ?? tcpPort
        self.fingerprint = fingerprint
        self.secret = secret
        try validate()
    }

    /// Re-checks every size/range/format constraint spec §3.1.3 places on this payload (not
    /// including the ≤ 512-byte total URL length, which depends on percent-encoding and is
    /// checked by `formatted()`/`parse(_:)` instead).
    public func validate() throws {
        guard version >= 1, version <= 999 else {
            throw ProtocolError.invalidPairingURL(field: "v", reason: "\(version) is not 1-3 decimal digits")
        }
        guard hostID.count == 16 else {
            throw ProtocolError.invalidPairingURL(field: "id", reason: "must be 16 bytes, got \(hostID.count)")
        }
        guard hostName.utf8.count <= 63 else {
            throw ProtocolError.invalidPairingURL(field: "n", reason: "exceeds 63 UTF-8 bytes")
        }
        guard !hostName.isEmpty else {
            throw ProtocolError.invalidPairingURL(field: "n", reason: "empty")
        }
        guard (1...Self.maxAddresses).contains(addresses.count) else {
            throw ProtocolError.invalidPairingURL(
                field: "a",
                reason: "\(addresses.count) addresses, must be 1...\(Self.maxAddresses)"
            )
        }
        for address in addresses {
            guard IPLiteral.isValid(address) else {
                throw ProtocolError.invalidPairingURL(field: "a", reason: "'\(address)' is not a valid IPv4/IPv6 literal")
            }
        }
        guard ProtocolConstants.validPortRange.contains(tcpPort), String(tcpPort).count <= 5 else {
            throw ProtocolError.invalidPairingURL(field: "p", reason: "\(tcpPort) is not a valid port")
        }
        guard ProtocolConstants.validPortRange.contains(udpPort), String(udpPort).count <= 5 else {
            throw ProtocolError.invalidPairingURL(field: "u", reason: "\(udpPort) is not a valid port")
        }
        guard fingerprint.count == 32 else {
            throw ProtocolError.invalidPairingURL(field: "fp", reason: "must be 32 bytes, got \(fingerprint.count)")
        }
        guard secret.count == 16 else {
            throw ProtocolError.invalidPairingURL(field: "s", reason: "must be 16 bytes, got \(secret.count)")
        }
    }

    /// Formats this payload as an `airmouse://pair?...` URL string.
    ///
    /// - Throws: `ProtocolError.pairingURLTooLarge` if the formatted string exceeds
    ///   `maxURLLength`; use `truncatingToFit` to drop trailing addresses instead.
    public func formatted() throws -> String {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.pairHost
        components.queryItems = [
            URLQueryItem(name: "v", value: String(version)),
            URLQueryItem(name: "id", value: hostID.b64u),
            URLQueryItem(name: "n", value: hostName),
            URLQueryItem(name: "a", value: addresses.joined(separator: ",")),
            URLQueryItem(name: "p", value: String(tcpPort)),
            URLQueryItem(name: "u", value: String(udpPort)),
            URLQueryItem(name: "fp", value: fingerprint.b64u),
            URLQueryItem(name: "s", value: secret.b64u),
        ]
        guard let string = components.url?.absoluteString ?? components.string else {
            throw ProtocolError.invalidPairingURL(field: "*", reason: "could not assemble a valid URL")
        }
        guard string.utf8.count <= Self.maxURLLength else {
            throw ProtocolError.pairingURLTooLarge(length: string.utf8.count)
        }
        return string
    }

    /// Builds a pairing URL, dropping trailing addresses (never truncating `secret` or any other
    /// field) until the formatted string fits `maxURLLength`. spec §3.1.3: "the host truncates the
    /// address list, not the secret, to stay within the limit."
    ///
    /// - Throws: `ProtocolError.pairingURLTooLarge` if even a single address does not fit.
    public static func truncatingToFit(
        version: Int,
        hostID: Data,
        hostName: String,
        addresses: [String],
        tcpPort: Int,
        udpPort: Int? = nil,
        fingerprint: Data,
        secret: Data
    ) throws -> PairingURL {
        // Pre-trim to the schema limit so a multi-homed host (VPN, hotspot, link-local IPv6) does not
        // fail validation before truncation gets a chance to run (found on a Mac with 14 addresses).
        var candidateAddresses = Array(addresses.prefix(Self.maxAddresses))
        while true {
            let candidate = try PairingURL(
                version: version,
                hostID: hostID,
                hostName: hostName,
                addresses: candidateAddresses,
                tcpPort: tcpPort,
                udpPort: udpPort,
                fingerprint: fingerprint,
                secret: secret
            )
            if let formatted = try? candidate.formatted(), formatted.utf8.count <= maxURLLength {
                return candidate
            }
            guard candidateAddresses.count > 1 else {
                let attempted = (try? candidate.formatted())?.utf8.count ?? 0
                throw ProtocolError.pairingURLTooLarge(length: attempted)
            }
            candidateAddresses.removeLast()
        }
    }

    /// Parses and validates an `airmouse://pair?...` URL string.
    public static func parse(_ urlString: String) throws -> PairingURL {
        guard urlString.utf8.count <= maxURLLength else {
            throw ProtocolError.pairingURLTooLarge(length: urlString.utf8.count)
        }
        guard let components = URLComponents(string: urlString) else {
            throw ProtocolError.invalidPairingURL(field: "*", reason: "not a valid URL")
        }
        guard components.scheme?.lowercased() == scheme else {
            throw ProtocolError.invalidPairingURL(field: "scheme", reason: "expected '\(scheme)'")
        }
        guard components.host == pairHost else {
            throw ProtocolError.invalidPairingURL(field: "host", reason: "expected '\(pairHost)'")
        }

        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }

        guard let versionString = value("v"), versionString.count <= 3, let version = Int(versionString) else {
            throw ProtocolError.invalidPairingURL(field: "v", reason: "missing or not 1-3 decimal digits")
        }

        guard let idString = value("id"), let hostID = Data(b64u: idString), hostID.count == 16 else {
            throw ProtocolError.invalidPairingURL(field: "id", reason: "missing or not b64u of 16 bytes")
        }

        guard let hostName = value("n"), !hostName.isEmpty, hostName.utf8.count <= 63 else {
            throw ProtocolError.invalidPairingURL(field: "n", reason: "missing or exceeds 63 UTF-8 bytes")
        }

        guard let addressesString = value("a"), !addressesString.isEmpty else {
            throw ProtocolError.invalidPairingURL(field: "a", reason: "missing")
        }
        let addresses = addressesString.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard (1...maxAddresses).contains(addresses.count) else {
            throw ProtocolError.invalidPairingURL(field: "a", reason: "\(addresses.count) addresses, must be 1...\(maxAddresses)")
        }
        for address in addresses {
            guard IPLiteral.isValid(address) else {
                throw ProtocolError.invalidPairingURL(field: "a", reason: "'\(address)' is not a valid IPv4/IPv6 literal")
            }
        }

        guard let tcpPortString = value("p"), tcpPortString.count <= 5, let tcpPort = Int(tcpPortString),
              ProtocolConstants.validPortRange.contains(tcpPort)
        else {
            throw ProtocolError.invalidPairingURL(field: "p", reason: "missing or not a valid port")
        }

        let udpPort: Int
        if let udpPortString = value("u") {
            guard udpPortString.count <= 5, let parsed = Int(udpPortString), ProtocolConstants.validPortRange.contains(parsed) else {
                throw ProtocolError.invalidPairingURL(field: "u", reason: "not a valid port")
            }
            udpPort = parsed
        } else {
            udpPort = tcpPort
        }

        guard let fingerprintString = value("fp"), let fingerprint = Data(b64u: fingerprintString), fingerprint.count == 32 else {
            throw ProtocolError.invalidPairingURL(field: "fp", reason: "missing or not b64u of 32 bytes")
        }

        guard let secretString = value("s"), let secret = Data(b64u: secretString), secret.count == 16 else {
            throw ProtocolError.invalidPairingURL(field: "s", reason: "missing or not b64u of 16 bytes")
        }

        return try PairingURL(
            version: version,
            hostID: hostID,
            hostName: hostName,
            addresses: addresses,
            tcpPort: tcpPort,
            udpPort: udpPort,
            fingerprint: fingerprint,
            secret: secret
        )
    }

    /// spec §3.1.3: "client rejects unknown values with E-PAIR-VERSION". This type only parses
    /// `v` as an integer; comparing it against the versions the caller speaks is policy left to
    /// the caller (mirroring `TXTRecord.supportsVersion(_:)`).
    public func isSupportedVersion(in supported: some Sequence<Int>) -> Bool {
        supported.contains(version)
    }
}
