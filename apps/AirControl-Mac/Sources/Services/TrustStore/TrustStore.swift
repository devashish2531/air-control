// TrustStore — spec §3.2.4 (trusted-device persistence), §5.6 (Trusted Devices window / revocation),
// §7.6 (20-device cap). Owned by the networking agent (assignment: "Services/TrustStore/").
//
// Conforms to both `AirControlCore.TrustStoreProtocol` (the shape `HostSession`/`PairingService`
// consult during TLS/pairing) and the shell's `TrustStoring` (`App/ServiceProtocols.swift`, the
// Trusted Devices window's DI slot) — the two protocols model the same records from different
// angles (`AirControlCrypto.Fingerprint` vs. a `String` id), so this actor is the single adapter
// between them rather than keeping two copies of the truth. Since both modules independently
// declare a type named `TrustedDeviceRecord`, every use of Core's below is spelled out as
// `CoreTrustedDeviceRecord` (a local typealias); the bare name always means the shell's.
//
// Persistence: per spec §3.2.4, the record's true Keychain counterpart is the client's *own*
// certificate (added during pairing, spec §3.2.2's `PairingService.recordTrustedClient`); this
// actor only owns the metadata document (`TrustedDevices.json`, spec §3.2.4) via the shell's
// `DocumentStore` (arch §6.3). Revocation removes the Keychain certificate item too (best-effort:
// no certificate to remove is not an error) so a revoked device's client cert can never
// re-authenticate even if this JSON were somehow restored.
import AirControlCore
import AirControlCrypto
import AirControlProtocol
import Foundation
import Security

/// Disambiguates `AirControlCore.TrustedDeviceRecord` from the shell's own same-named type
/// (`App/ServiceProtocols.swift`) — see this file's header.
public typealias CoreTrustedDeviceRecord = AirControlCore.TrustedDeviceRecord

public actor TrustStore: TrustStoreProtocol, TrustStoring {
    private static let relativePath = "TrustedDevices.json"
    private static let schemaName = "trusted-devices"
    private static let schemaVersion = 1

    private let documentStore: DocumentStore
    private var records: [Fingerprint: CoreTrustedDeviceRecord] = [:]
    private var didBootstrap = false
    /// Invoked whenever a fingerprint's record is revoked, so `SessionManager` can close any live
    /// session for that device within 1 s (spec §5.6). Set once by `HostFeature.make`.
    public var onRevoked: (@Sendable (Fingerprint) async -> Void)?

    public func setOnRevoked(_ handler: @escaping @Sendable (Fingerprint) async -> Void) {
        onRevoked = handler
    }

    public init(documentStore: DocumentStore) {
        self.documentStore = documentStore
    }

    private struct Document: Codable, Sendable {
        var records: [CoreTrustedDeviceRecord]
    }

    private func ensureBootstrapped() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        do {
            if let loaded = try await documentStore.load(
                Document.self,
                relativePath: Self.relativePath,
                schemaName: Self.schemaName,
                schemaVersion: Self.schemaVersion
            ) {
                for record in loaded.records {
                    records[record.fingerprint] = record
                }
            }
        } catch {
            Log.store.error("Failed to load TrustedDevices.json, starting fresh: \(String(describing: error), privacy: .public)")
        }
    }

    private func persist() async {
        let document = Document(records: Array(records.values))
        try? await documentStore.save(
            document,
            relativePath: Self.relativePath,
            schemaName: Self.schemaName,
            schemaVersion: Self.schemaVersion
        )
    }

    // MARK: - AirControlCore.TrustStoreProtocol

    public func list() async -> [CoreTrustedDeviceRecord] {
        await ensureBootstrapped()
        return Array(records.values)
    }

    public func lookup(fingerprint: Fingerprint) async -> CoreTrustedDeviceRecord? {
        await ensureBootstrapped()
        return records[fingerprint]
    }

    @discardableResult
    public func add(_ record: CoreTrustedDeviceRecord) async -> Bool {
        await ensureBootstrapped()
        if records[record.fingerprint] == nil {
            // spec §7.6 / §11.3: 20 trusted devices per host.
            guard records.count < ProtocolConstants.maxTrustedDevicesPerHost else { return false }
        }
        records[record.fingerprint] = record
        await persist()
        return true
    }

    public func revoke(fingerprint: Fingerprint) async {
        await ensureBootstrapped()
        guard var record = records[fingerprint] else { return }
        record.revoked = true
        records[fingerprint] = record
        await persist()
        deleteKeychainCertificate(fingerprint: fingerprint)
        if let onRevoked {
            await onRevoked(fingerprint)
        }
    }

    public func updateLastSeen(fingerprint: Fingerprint, date: Date) async {
        await ensureBootstrapped()
        guard var record = records[fingerprint] else { return }
        record.lastSeen = date
        records[fingerprint] = record
        await persist()
    }

    public func update(_ record: CoreTrustedDeviceRecord) async {
        await ensureBootstrapped()
        records[record.fingerprint] = record
        await persist()
    }

    public func remove(fingerprint: Fingerprint) async {
        await ensureBootstrapped()
        records.removeValue(forKey: fingerprint)
        await persist()
        deleteKeychainCertificate(fingerprint: fingerprint)
    }

    /// Fast decision surface for the TLS verify block (spec §3.2.1,
    /// `AirControlCrypto.PinningPolicy.hostDecision`'s `trustedFingerprints`/`pendingConnectionCount`
    /// inputs). Non-revoked fingerprints only (spec: "trusted store and not revoked").
    public func trustedFingerprints() async -> Set<Fingerprint> {
        await ensureBootstrapped()
        return Set(records.values.filter { !$0.revoked }.map { $0.fingerprint })
    }

    private func deleteKeychainCertificate(fingerprint: Fingerprint) {
        let label = "AirControl Trusted Client \(fingerprint.hexString)"
        let query: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecAttrLabel: label,
            kSecUseDataProtectionKeychain: false,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Shell's TrustStoring (App/ServiceProtocols.swift)

    public func listDevices() async -> [TrustedDeviceRecord] {
        await ensureBootstrapped()
        return records.values.map(Self.shellRecord(from:)).sorted { $0.firstPaired < $1.firstPaired }
    }

    public func revoke(id: String) async throws {
        await ensureBootstrapped()
        guard let fingerprint = Fingerprint(hexString: id), records[fingerprint] != nil else {
            throw TrustStoreError.notFound(id: id)
        }
        await revoke(fingerprint: fingerprint)
    }

    public func revokeAll() async throws {
        await ensureBootstrapped()
        for fingerprint in records.keys {
            await revoke(fingerprint: fingerprint)
        }
    }

    public func setAllowScripts(_ allow: Bool, forDeviceID id: String) async throws {
        await ensureBootstrapped()
        guard let fingerprint = Fingerprint(hexString: id), var record = records[fingerprint] else {
            throw TrustStoreError.notFound(id: id)
        }
        record.allowScripts = allow
        records[fingerprint] = record
        await persist()
    }

    public func rename(id: String, to newName: String) async throws {
        await ensureBootstrapped()
        guard let fingerprint = Fingerprint(hexString: id), var record = records[fingerprint] else {
            throw TrustStoreError.notFound(id: id)
        }
        record.localAlias = newName
        records[fingerprint] = record
        await persist()
    }

    private static func shellRecord(from record: CoreTrustedDeviceRecord) -> TrustedDeviceRecord {
        TrustedDeviceRecord(
            id: record.fingerprint.hexString,
            name: record.localAlias ?? record.name,
            model: record.model,
            osVersion: record.osVersion,
            fingerprintShort: Redact.fingerprintPrefix(record.fingerprint.hexString),
            firstPaired: record.firstPaired,
            lastSeen: record.lastSeen,
            allowScripts: record.allowScripts,
            revoked: record.revoked
        )
    }
}
