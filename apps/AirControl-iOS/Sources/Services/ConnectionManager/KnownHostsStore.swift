// Services/ConnectionManager/KnownHostsStore.swift
// Client-side trusted-host persistence — spec §3.2.4's client row: "hostID, hostFP, name, model,
// firstPaired, lastConnected, lastKnownAddresses[] (≤ 6, with timestamps), tcpPort, udpPort,
// qrAddresses[], perHostSettingsOverride?, macroCacheRevision" — plus "last-used host id" for
// auto-connect (spec §4.5.5: "if a trusted target exists and auto-connect is on → Connecting
// immediately").
//
// `AirControlCore.TrustedDeviceRecord` is documented as host-side-shaped ("from the host's point of
// view"), but it is the only `Codable`, versionable trust record `AirControlCore` exports, and this
// agent's brief explicitly calls for "`TrustStoreProtocol` + `TrustedDeviceRecord(...)`" here —
// so this store reinterprets its fields for the client's side of the same trust relationship
// (`fingerprint` = the host's certificate FP, `name`/`model`/`osVersion` = the Mac's own identity,
// `allowScripts` unused client-side). The connection-specific extras `TrustedDeviceRecord` has no
// field for (`lastKnownAddresses`, ports, `qrAddresses`) live in a second sibling document,
// `KnownHostConnectionInfo`, keyed by the same fingerprint — noted as a deviation in the final
// report rather than widening a cross-module type mid-flight.

import Foundation
import AirControlCore
import AirControlCrypto
import AirControlProtocol

/// The per-host connection extras spec §3.2.4 lists that `TrustedDeviceRecord` has no field for.
public struct KnownHostConnectionInfo: Codable, Sendable, Equatable {
    /// One previously-successful address, newest first (spec: "≤ 6, with timestamps").
    public struct TimestampedAddress: Codable, Sendable, Equatable {
        public var address: String
        public var lastConnected: Date

        public init(address: String, lastConnected: Date) {
            self.address = address
            self.lastConnected = lastConnected
        }
    }

    public var tcpPort: Int
    public var udpPort: Int
    /// Newest first, capped at `maxLastKnownAddresses` (spec §3.2.4 / §4.5.4: "max 6, LRU").
    public var lastKnownAddresses: [TimestampedAddress]
    /// The QR's original address list, in QR order (spec §3.3.2 candidate tier 3).
    public var qrAddresses: [String]
    /// The TXT/QR `id` (host ID, 16 bytes) — not a `TrustedDeviceRecord` field, but needed to
    /// match a live Bonjour browse result to this trust record (spec §3.1.2: "The client uses
    /// `id` to match a trusted-host record").
    public var hostID: Data?

    public static let maxLastKnownAddresses = 6

    public init(tcpPort: Int, udpPort: Int, lastKnownAddresses: [TimestampedAddress] = [], qrAddresses: [String] = [], hostID: Data? = nil) {
        self.tcpPort = tcpPort
        self.udpPort = udpPort
        self.lastKnownAddresses = lastKnownAddresses
        self.qrAddresses = qrAddresses
        self.hostID = hostID
    }

    /// Moves `address` to the front (LRU), trims to `maxLastKnownAddresses` (spec §4.5.4: "After a
    /// hostID has connected successfully, its resolved IP is appended to `lastKnownAddresses`").
    mutating func recordSuccessfulAddress(_ address: String, at date: Date) {
        lastKnownAddresses.removeAll { $0.address == address }
        lastKnownAddresses.insert(TimestampedAddress(address: address, lastConnected: date), at: 0)
        if lastKnownAddresses.count > Self.maxLastKnownAddresses {
            lastKnownAddresses.removeLast(lastKnownAddresses.count - Self.maxLastKnownAddresses)
        }
    }
}

/// The two documents this store persists under `Application Support/AirControl/`.
private struct KnownHostsDocument: Codable, Sendable {
    var records: [TrustedDeviceRecord] = []
}

private struct ConnectionInfoDocument: Codable, Sendable {
    /// Keyed by `TrustedDeviceRecord.id` (fingerprint hex string).
    var infoByHostID: [String: KnownHostConnectionInfo] = [:]
}

/// `TrustStoreProtocol` conformer over `DocumentStore` (arch §6.3's generic JSON store), plus the
/// connection extras above and the "last-used host" id for auto-connect. One instance is shared
/// app-wide via `ConnectionFeature.make(environment:)`.
public actor KnownHostsStore: TrustStoreProtocol {
    private let documentStore: DocumentStore

    private static let hostsDescriptor = DocumentDescriptor<KnownHostsDocument>(
        relativePath: "TrustedHosts.json",
        schemaName: "trusted-hosts",
        currentVersion: 1,
        defaultValue: { KnownHostsDocument() }
    )
    private static let connectionInfoDescriptor = DocumentDescriptor<ConnectionInfoDocument>(
        relativePath: "TrustedHostConnectionInfo.json",
        schemaName: "trusted-host-connection-info",
        currentVersion: 1,
        defaultValue: { ConnectionInfoDocument() }
    )

    public init(documentStore: DocumentStore) {
        self.documentStore = documentStore
    }

    // MARK: - TrustStoreProtocol

    public func list() async -> [TrustedDeviceRecord] {
        await documentStore.load(Self.hostsDescriptor).records
    }

    public func lookup(fingerprint: Fingerprint) async -> TrustedDeviceRecord? {
        await documentStore.load(Self.hostsDescriptor).records.first { $0.fingerprint == fingerprint }
    }

    @discardableResult
    public func add(_ record: TrustedDeviceRecord) async -> Bool {
        var document = await documentStore.load(Self.hostsDescriptor)
        if let index = document.records.firstIndex(where: { $0.fingerprint == record.fingerprint }) {
            document.records[index] = record
        } else {
            guard document.records.count < ProtocolConstants.maxTrustedHostsPerClient else { return false }
            document.records.append(record)
        }
        try? await documentStore.save(document, descriptor: Self.hostsDescriptor)
        return true
    }

    public func revoke(fingerprint: Fingerprint) async {
        var document = await documentStore.load(Self.hostsDescriptor)
        guard let index = document.records.firstIndex(where: { $0.fingerprint == fingerprint }) else { return }
        document.records[index].revoked = true
        try? await documentStore.save(document, descriptor: Self.hostsDescriptor)
    }

    public func updateLastSeen(fingerprint: Fingerprint, date: Date) async {
        var document = await documentStore.load(Self.hostsDescriptor)
        guard let index = document.records.firstIndex(where: { $0.fingerprint == fingerprint }) else { return }
        document.records[index].lastSeen = date
        try? await documentStore.save(document, descriptor: Self.hostsDescriptor)
    }

    public func update(_ record: TrustedDeviceRecord) async {
        var document = await documentStore.load(Self.hostsDescriptor)
        guard let index = document.records.firstIndex(where: { $0.fingerprint == record.fingerprint }) else { return }
        document.records[index] = record
        try? await documentStore.save(document, descriptor: Self.hostsDescriptor)
    }

    /// spec §4.1.3 "Forget": removes the record and its connection-info sibling (macro cache
    /// removal is the Macros feature's own responsibility on the same fingerprint).
    public func remove(fingerprint: Fingerprint) async {
        var document = await documentStore.load(Self.hostsDescriptor)
        document.records.removeAll { $0.fingerprint == fingerprint }
        try? await documentStore.save(document, descriptor: Self.hostsDescriptor)

        var infoDocument = await documentStore.load(Self.connectionInfoDescriptor)
        infoDocument.infoByHostID.removeValue(forKey: fingerprint.hexString)
        try? await documentStore.save(infoDocument, descriptor: Self.connectionInfoDescriptor)
    }

    // MARK: - Connection info extras (spec §3.2.4's fields `TrustedDeviceRecord` has none for)

    public func connectionInfo(fingerprint: Fingerprint) async -> KnownHostConnectionInfo? {
        await documentStore.load(Self.connectionInfoDescriptor).infoByHostID[fingerprint.hexString]
    }

    /// Seeds/updates the ports + QR address list (spec §3.2.2: on first successful pairing).
    public func setConnectionInfo(_ info: KnownHostConnectionInfo, fingerprint: Fingerprint) async {
        var document = await documentStore.load(Self.connectionInfoDescriptor)
        document.infoByHostID[fingerprint.hexString] = info
        try? await documentStore.save(document, descriptor: Self.connectionInfoDescriptor)
    }

    /// spec §4.5.4: "After a hostID has connected successfully, its resolved IP is appended to
    /// `lastKnownAddresses` (max 6, LRU)."
    public func recordSuccessfulConnection(fingerprint: Fingerprint, address: String, at date: Date = Date()) async {
        var document = await documentStore.load(Self.connectionInfoDescriptor)
        var info = document.infoByHostID[fingerprint.hexString] ?? KnownHostConnectionInfo(tcpPort: ProtocolConstants.defaultTCPPort, udpPort: ProtocolConstants.defaultUDPPort)
        info.recordSuccessfulAddress(address, at: date)
        document.infoByHostID[fingerprint.hexString] = info
        try? await documentStore.save(document, descriptor: Self.connectionInfoDescriptor)
    }

    // MARK: - Last-used host (spec §4.5.5 auto-connect)

    /// The most recently connected trusted host's fingerprint hex, for auto-connect. Backed
    /// directly by `UserDefaults` (`UserDefaultsKey.lastHostID`, already defined by
    /// `Services/DocumentStore/UserSettings.swift`) rather than duplicating a key — `nonisolated`
    /// since `UserDefaults` is thread-safe and callers on the main actor (`UserSettings`) read/
    /// write the same key without going through this actor.
    public nonisolated var lastUsedHostFingerprintHex: String? {
        get { UserDefaults.standard.string(forKey: UserDefaultsKey.lastHostID) }
    }

    public nonisolated func setLastUsedHost(fingerprint: Fingerprint?) {
        UserDefaults.standard.set(fingerprint?.hexString, forKey: UserDefaultsKey.lastHostID)
    }
}
