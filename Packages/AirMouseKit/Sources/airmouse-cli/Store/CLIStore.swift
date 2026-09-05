// Store/CLIStore.swift
// Persists `airmouse-cli`'s own client identity and the hosts it has paired with, as JSON under
// `~/.airmouse-cli/` (0600 file perms, 0700 directory) — deliberately *not* the Keychain-backed
// `AirMouseCrypto.IdentityStore`/`IdentityFactory.makeIdentity` path (spec §7.1 Path A), because a
// CLI tool should work headlessly (CI, SSH) without Keychain prompts, and because its identity only
// needs to be *stable across invocations*, not hardware-backed. The certificate this produces still
// goes through `AirMouseCrypto.CertificateBuilder` (spec §3.2.1: self-signed P-256, 10-year validity,
// EKU serverAuth+clientAuth), so its shape and fingerprinting exactly match what the apps mint.
//
// `connect` (trusted reconnect, spec §3.3.1) needs the *same* certificate `pair` used, or the host's
// `TrustedDevices` lookup by client fingerprint will fail (spec §3.2.4) — hence persisting the raw
// P-256 key + DER certificate instead of minting a fresh ephemeral identity per invocation
// (`AirMouseCrypto.IdentityFactory.makeEphemeralIdentity`, which is deliberately never persisted).
import AirMouseCrypto
import AirMouseProtocol
import CryptoKit
import Foundation
import Security

/// One `airmouse-cli` client identity, persisted as raw key material + certificate DER.
struct IdentityRecord: Codable {
    var privateKeyRaw: Data
    var certificateDER: Data
    var commonName: String
    var fingerprintHex: String
}

/// One previously-paired host (spec §3.2.4's `TrustedHosts.json`, scoped down for the CLI: no
/// Keychain-stored host certificate, since the CLI re-validates by fingerprint alone at each connect).
struct TrustedHostRecord: Codable {
    var hostIDB64u: String
    var name: String
    var fingerprintHex: String
    var address: String
    var tcpPort: Int
    var udpPort: Int
    var pairedAt: Date
}

enum CLIStoreError: Error, CustomStringConvertible {
    case keyImportFailed(String)
    case certificateImportFailed
    case identityCreationFailed

    var description: String {
        switch self {
        case .keyImportFailed(let reason): return "could not rebuild the stored CLI identity: \(reason)"
        case .certificateImportFailed: return "stored CLI certificate is corrupt"
        case .identityCreationFailed: return "SecIdentityCreate failed for the stored CLI identity"
        }
    }
}

enum CLIStore {
    /// `~/.airmouse-cli/`.
    static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".airmouse-cli", isDirectory: true)
    }

    private static var identityFileURL: URL { directoryURL.appendingPathComponent("identity.json") }
    private static var trustedHostsFileURL: URL { directoryURL.appendingPathComponent("trusted-hosts.json") }

    // MARK: - Identity

    /// Loads the persisted identity, or generates and persists a new one on first use. Returns the
    /// `SecIdentity` ready for `sec_identity_create`/TLS local-identity use plus its fingerprint.
    static func loadOrCreateIdentity() throws -> (secIdentity: SecIdentity, fingerprint: Fingerprint) {
        try ensureDirectoryExists()
        let record: IdentityRecord
        if let data = FileManager.default.contents(atPath: identityFileURL.path),
           let decoded = try? JSONDecoder().decode(IdentityRecord.self, from: data) {
            record = decoded
        } else {
            record = try makeAndPersistIdentity()
        }
        return try buildSecIdentity(from: record)
    }

    private static func makeAndPersistIdentity() throws -> IdentityRecord {
        let privateKey = P256.Signing.PrivateKey()
        let commonName = "AirMouse CLI Client \(Data(SystemRandom.bytes(16)).b64u)"
        let output = try CertificateBuilder.makeSelfSigned(privateKey: privateKey, commonName: commonName)
        let record = IdentityRecord(
            privateKeyRaw: privateKey.rawRepresentation,
            certificateDER: output.der,
            commonName: commonName,
            fingerprintHex: output.fingerprint.hexString
        )
        let data = try JSONEncoder().encode(record)
        try write(data, to: identityFileURL)
        return record
    }

    /// Rebuilds a transient (never Keychain-persisted — see type header) `SecIdentity` from the
    /// stored raw key + certificate, the same `SecKeyCreateWithData` + `SecCertificateCreateWithData`
    /// + `SecIdentityCreate` recipe `AirMouseCrypto.IdentityFactory` uses for its own ephemeral path.
    private static func buildSecIdentity(from record: IdentityRecord) throws -> (SecIdentity, Fingerprint) {
        let privateKey: P256.Signing.PrivateKey
        do {
            privateKey = try P256.Signing.PrivateKey(rawRepresentation: record.privateKeyRaw)
        } catch {
            throw CLIStoreError.keyImportFailed(String(describing: error))
        }

        let creationAttributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits: 256,
        ]
        var keyError: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(
            privateKey.x963Representation as CFData,
            creationAttributes as CFDictionary,
            &keyError
        ) else {
            throw CLIStoreError.keyImportFailed(keyError.map { String(describing: $0.takeRetainedValue()) } ?? "unknown")
        }

        guard let secCertificate = SecCertificateCreateWithData(nil, record.certificateDER as CFData) else {
            throw CLIStoreError.certificateImportFailed
        }

        guard let identity = SecIdentityCreate(nil, secCertificate, secKey) else {
            throw CLIStoreError.identityCreationFailed
        }

        guard let fingerprint = Fingerprint(hexString: record.fingerprintHex) else {
            throw CLIStoreError.certificateImportFailed
        }
        return (identity, fingerprint)
    }

    // MARK: - Trusted hosts

    static func loadTrustedHosts() -> [TrustedHostRecord] {
        guard let data = FileManager.default.contents(atPath: trustedHostsFileURL.path),
              let decoded = try? JSONDecoder().decode([TrustedHostRecord].self, from: data)
        else { return [] }
        return decoded
    }

    /// Upserts `record`, matched by `hostIDB64u`, newest first.
    static func saveTrustedHost(_ record: TrustedHostRecord) throws {
        try ensureDirectoryExists()
        var hosts = loadTrustedHosts().filter { $0.hostIDB64u != record.hostIDB64u }
        hosts.insert(record, at: 0)
        let data = try JSONEncoder().encode(hosts)
        try write(data, to: trustedHostsFileURL)
    }

    /// Finds a previously-paired host by address (exact match) or display name (case-insensitive),
    /// most-recently-paired first.
    static func findTrustedHost(matching host: String) -> TrustedHostRecord? {
        let hosts = loadTrustedHosts()
        return hosts.first { $0.address == host } ?? hosts.first { $0.name.lowercased() == host.lowercased() }
    }

    // MARK: - File helpers

    private static func ensureDirectoryExists() throws {
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
    }

    private static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Minimal `SecRandomCopyBytes` wrapper so this file needs no `AirMouseCrypto` internal (its
/// `SecureRandom` is not public API); used only for the identity's cosmetic common-name suffix.
private enum SystemRandom {
    static func bytes(_ count: Int) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &output)
        return output
    }
}
