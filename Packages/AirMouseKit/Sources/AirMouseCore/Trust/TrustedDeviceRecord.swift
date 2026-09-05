import Foundation
import AirMouseCrypto

/// A trusted client device, from the host's point of view (spec §3.2.4's `TrustedDevices.json`
/// record): `clientID` (FP), `name`, `model`, `osVersion`, `firstPaired`, `lastSeen`,
/// `localAlias?`, `allowScripts` (false), `revoked` (false).
///
/// `Fingerprint` (owned by `AirMouseCrypto`) is not `Codable` there, and this module deliberately
/// does not retroactively conform it (a cross-module `extension Fingerprint: Codable` risks a
/// duplicate-conformance clash if another module independently adds the same one — see CLAUDE.md's
/// parallel-agents note) — `TrustedDeviceRecord` instead implements `Codable` by hand, storing the
/// fingerprint as its 64-character hex string (`Fingerprint.hexString`/`init(hexString:)`).
public struct TrustedDeviceRecord: Sendable, Equatable, Identifiable {
    /// The client's certificate fingerprint — the sole basis of trust (spec §3.2.1) and this
    /// record's identity.
    public var fingerprint: Fingerprint
    public var name: String
    public var model: String
    public var osVersion: String
    public var firstPaired: Date
    public var lastSeen: Date
    public var localAlias: String?
    public var allowScripts: Bool
    public var revoked: Bool

    public var id: String { fingerprint.hexString }

    public init(
        fingerprint: Fingerprint,
        name: String,
        model: String,
        osVersion: String,
        firstPaired: Date,
        lastSeen: Date,
        localAlias: String? = nil,
        allowScripts: Bool = false,
        revoked: Bool = false
    ) {
        self.fingerprint = fingerprint
        self.name = name
        self.model = model
        self.osVersion = osVersion
        self.firstPaired = firstPaired
        self.lastSeen = lastSeen
        self.localAlias = localAlias
        self.allowScripts = allowScripts
        self.revoked = revoked
    }
}

extension TrustedDeviceRecord: Codable {
    private enum CodingKeys: String, CodingKey {
        case fingerprint, name, model, osVersion, firstPaired, lastSeen, localAlias, allowScripts, revoked
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hex = try container.decode(String.self, forKey: .fingerprint)
        guard let fingerprint = Fingerprint(hexString: hex) else {
            throw DecodingError.dataCorruptedError(
                forKey: .fingerprint,
                in: container,
                debugDescription: "Not a 64-char hex fingerprint: \(hex)"
            )
        }
        self.fingerprint = fingerprint
        name = try container.decode(String.self, forKey: .name)
        model = try container.decode(String.self, forKey: .model)
        osVersion = try container.decode(String.self, forKey: .osVersion)
        firstPaired = try container.decode(Date.self, forKey: .firstPaired)
        lastSeen = try container.decode(Date.self, forKey: .lastSeen)
        localAlias = try container.decodeIfPresent(String.self, forKey: .localAlias)
        allowScripts = try container.decode(Bool.self, forKey: .allowScripts)
        revoked = try container.decode(Bool.self, forKey: .revoked)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fingerprint.hexString, forKey: .fingerprint)
        try container.encode(name, forKey: .name)
        try container.encode(model, forKey: .model)
        try container.encode(osVersion, forKey: .osVersion)
        try container.encode(firstPaired, forKey: .firstPaired)
        try container.encode(lastSeen, forKey: .lastSeen)
        try container.encodeIfPresent(localAlias, forKey: .localAlias)
        try container.encode(allowScripts, forKey: .allowScripts)
        try container.encode(revoked, forKey: .revoked)
    }
}
