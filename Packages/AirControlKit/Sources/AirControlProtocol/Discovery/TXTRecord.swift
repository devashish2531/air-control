import Foundation

/// The Bonjour TXT record both services register (spec §3.1.1: "the same TXT record"). spec
/// §3.1.2:
///
/// | Key | Value | Encoding | Example |
/// |---|---|---|---|
/// | `v` | Supported protocol major versions, comma-separated ascending | ASCII digits | `1` |
/// | `n` | Host display name (≤ 63 bytes UTF-8, truncated on a grapheme boundary) | UTF-8 | `Devashish's Mac mini` |
/// | `id` | Host ID: 16 random bytes, stable per install | b64u (22 chars) | `k3Jq…` |
/// | `fp` | First 16 bytes of the host certificate FP | b64u (22 chars) | `Zx8…` |
/// | `m` | Machine model identifier | ASCII | `Mac15,6` |
/// | `tp` | TCP control port | ASCII decimal | `47800` |
/// | `up` | UDP motion port | ASCII decimal | `47800` |
///
/// "Each key/value pair ≤ 255 bytes; total TXT ≤ 400 bytes." spec §3.1.1 cross-talk guard (R-10):
/// "a browse result whose TXT lacks `v` or whose `v` list does not include a version the client
/// speaks is hidden from the Devices list" — `supportsVersion(_:)` implements the second half of
/// that check; parsing itself already enforces the first half (`v` is required).
public struct TXTRecord: Sendable, Equatable {
    /// `v`: supported protocol major versions, ascending.
    public var supportedVersions: [Int]
    /// `n`: host display name, ≤ 63 bytes UTF-8.
    public var hostName: String
    /// `id`: 16 random bytes, stable per install.
    public var hostID: Data
    /// `fp`: first 16 bytes of the host certificate fingerprint (a hint only — trust is decided by
    /// the full pinned certificate during TLS, spec §3.2.4).
    public var fingerprintPrefix: Data
    /// `m`: machine model identifier, e.g. `Mac15,6`.
    public var machineModel: String
    /// `tp`: TCP control port.
    public var tcpPort: Int
    /// `up`: UDP motion port.
    public var udpPort: Int

    /// Constructs and validates a TXT record from already-typed fields (the host side, building
    /// one to register).
    public init(
        supportedVersions: [Int],
        hostName: String,
        hostID: Data,
        fingerprintPrefix: Data,
        machineModel: String,
        tcpPort: Int,
        udpPort: Int
    ) throws {
        self.supportedVersions = supportedVersions
        self.hostName = hostName
        self.hostID = hostID
        self.fingerprintPrefix = fingerprintPrefix
        self.machineModel = machineModel
        self.tcpPort = tcpPort
        self.udpPort = udpPort
        try validate()
    }

    /// Parses and validates a TXT record from the raw string dictionary a Bonjour browse result
    /// hands back (the client side).
    public init(parsing dict: [String: String]) throws {
        guard let versionsString = dict["v"], !versionsString.isEmpty else {
            throw ProtocolError.invalidTXTRecord(field: "v", reason: "missing")
        }
        let rawVersionParts = versionsString.split(separator: ",", omittingEmptySubsequences: false)
        let versions = rawVersionParts.compactMap { Int($0) }
        guard versions.count == rawVersionParts.count, !versions.isEmpty else {
            throw ProtocolError.invalidTXTRecord(field: "v", reason: "not ASCII-digit, comma-separated integers")
        }
        guard versions == versions.sorted() else {
            throw ProtocolError.invalidTXTRecord(field: "v", reason: "not ascending")
        }

        guard let name = dict["n"] else {
            throw ProtocolError.invalidTXTRecord(field: "n", reason: "missing")
        }

        guard let idString = dict["id"], let idData = Data(b64u: idString) else {
            throw ProtocolError.invalidTXTRecord(field: "id", reason: "missing or not valid b64u")
        }

        guard let fpString = dict["fp"], let fpData = Data(b64u: fpString) else {
            throw ProtocolError.invalidTXTRecord(field: "fp", reason: "missing or not valid b64u")
        }

        guard let model = dict["m"], !model.isEmpty else {
            throw ProtocolError.invalidTXTRecord(field: "m", reason: "missing")
        }

        guard let tcpPortString = dict["tp"], let tcpPortValue = Int(tcpPortString) else {
            throw ProtocolError.invalidTXTRecord(field: "tp", reason: "missing or not an integer")
        }

        guard let udpPortString = dict["up"], let udpPortValue = Int(udpPortString) else {
            throw ProtocolError.invalidTXTRecord(field: "up", reason: "missing or not an integer")
        }

        self.supportedVersions = versions
        self.hostName = name
        self.hostID = idData
        self.fingerprintPrefix = fpData
        self.machineModel = model
        self.tcpPort = tcpPortValue
        self.udpPort = udpPortValue
        try validate()
    }

    /// Re-checks every size/range constraint spec §3.1.2 places on this record. Called by both
    /// initializers; exposed publicly so a caller that mutates a record in place (unusual, but not
    /// prevented by the value type) can re-validate before registering/trusting it.
    public func validate() throws {
        guard !supportedVersions.isEmpty else {
            throw ProtocolError.invalidTXTRecord(field: "v", reason: "empty")
        }
        guard supportedVersions == supportedVersions.sorted() else {
            throw ProtocolError.invalidTXTRecord(field: "v", reason: "not ascending")
        }
        guard hostName.utf8.count <= 63 else {
            throw ProtocolError.invalidTXTRecord(field: "n", reason: "exceeds 63 UTF-8 bytes")
        }
        guard hostID.count == 16 else {
            throw ProtocolError.invalidTXTRecord(field: "id", reason: "must be 16 bytes, got \(hostID.count)")
        }
        guard fingerprintPrefix.count == 16 else {
            throw ProtocolError.invalidTXTRecord(field: "fp", reason: "must be 16 bytes, got \(fingerprintPrefix.count)")
        }
        guard !machineModel.isEmpty else {
            throw ProtocolError.invalidTXTRecord(field: "m", reason: "empty")
        }
        guard ProtocolConstants.validPortRange.contains(tcpPort) || tcpPort == ProtocolConstants.defaultTCPPort else {
            throw ProtocolError.invalidTXTRecord(field: "tp", reason: "\(tcpPort) outside a valid port range")
        }
        guard ProtocolConstants.validPortRange.contains(udpPort) || udpPort == ProtocolConstants.defaultUDPPort else {
            throw ProtocolError.invalidTXTRecord(field: "up", reason: "\(udpPort) outside a valid port range")
        }

        let entries = serialize()
        for (key, value) in entries {
            let entrySize = key.utf8.count + value.utf8.count
            guard entrySize <= 255 else {
                throw ProtocolError.invalidTXTRecord(field: key, reason: "entry is \(entrySize) bytes, exceeding 255")
            }
        }
        let totalSize = entries.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
        guard totalSize <= 400 else {
            throw ProtocolError.invalidTXTRecord(field: "*", reason: "total TXT size \(totalSize) bytes exceeds 400")
        }
    }

    /// Serializes to the raw string dictionary a Bonjour TXT record is built from.
    public func serialize() -> [String: String] {
        [
            "v": supportedVersions.map(String.init).joined(separator: ","),
            "n": hostName,
            "id": hostID.b64u,
            "fp": fingerprintPrefix.b64u,
            "m": machineModel,
            "tp": String(tcpPort),
            "up": String(udpPort),
        ]
    }

    /// spec §3.1.1's cross-talk guard (R-10): whether this record advertises a protocol version
    /// the caller speaks.
    public func supportsVersion(_ version: Int) -> Bool {
        supportedVersions.contains(version)
    }
}
