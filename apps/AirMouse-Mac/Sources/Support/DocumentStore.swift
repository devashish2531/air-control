// arch §6.3 "Application Support JSON documents" and "Migration policy".
//
// Every document is `{ "schema": "<name>/<int>", ... }`, written atomically, read through
// `DocumentStore.load(_:migrating:)`. Deviation: the assignment prose for this file said
// "~/Library/Application Support/Air Mouse/", but arch §6.3's own table of concrete documents uses
// "~/Library/Application Support/AirMouseHelper/..." for every host-side path. Arch §6.3 is authoritative
// here (it is the doc that also names TrustedDevices.json/Macros.json), so `defaultBaseDirectory` matches
// it; call out this discrepancy if another agent expected the other folder name.
import Foundation

public enum DocumentStoreError: Error, Sendable, Equatable {
    /// The document on disk declares a schema version newer than this build understands. The file has
    /// already been backed up to `<name>.json.bak-<timestamp>` by the time this is thrown.
    case newerSchema(name: String, found: Int, supported: Int)
    /// The document could not be parsed, or its `schema` field was missing/malformed. Also already backed up.
    case corrupt(underlying: String)
    /// The document's schema `name` did not match what the caller asked to load.
    case schemaNameMismatch(expected: String, found: String)
}

/// Codable JSON document store for `~/Library/Application Support/AirMouseHelper/` (arch §6.3). One
/// instance is safe to share across the app; all I/O happens on the actor's executor.
public actor DocumentStore {
    /// A pure migration step applied when a stored document's version equals `fromVersion`. Returns the
    /// document advanced by exactly one version; `DocumentStore` applies migrators repeatedly until the
    /// document reaches the target `schemaVersion` or no matching migrator remains.
    public struct Migration: Sendable {
        public let fromVersion: Int
        public let apply: @Sendable (JSONValue) -> JSONValue

        public init(fromVersion: Int, apply: @escaping @Sendable (JSONValue) -> JSONValue) {
            self.fromVersion = fromVersion
            self.apply = apply
        }
    }

    public static var defaultBaseDirectory: URL {
        // `AIRMOUSE_DATA_DIR` redirects every document (trust store, macros, host id) to another folder.
        // `--loopback` and the integration harness use a temporary folder so throwaway pairings never
        // fill the real 20-device trust store (which is exactly what happened on 2026-09-05).
        if let override = ProcessInfo.processInfo.environment["AIRMOUSE_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AirMouseHelper", isDirectory: true)
    }

    private let baseDirectory: URL
    private let fileManager: FileManager

    public init(baseDirectory: URL = DocumentStore.defaultBaseDirectory, fileManager: FileManager = .default) {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager
    }

    /// Loads and decodes the document at `relativePath` (e.g. `"TrustedDevices.json"`), applying
    /// `migrations` until the stored version reaches `schemaVersion`. Returns `nil` if the file does not
    /// exist yet (a fresh install). A newer-than-known schema or a corrupt file is backed up alongside the
    /// original under `<name>.json.bak-<timestamp>` and the corresponding error is thrown (arch §6.3).
    public func load<T: Decodable & Sendable>(
        _ type: T.Type,
        relativePath: String,
        schemaName: String,
        schemaVersion: Int,
        migrations: [Migration] = []
    ) throws -> T? {
        let url = baseDirectory.appendingPathComponent(relativePath)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DocumentStoreError.corrupt(underlying: String(describing: error))
        }

        let root: JSONValue
        do {
            root = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            try? backUp(url: url)
            throw DocumentStoreError.corrupt(underlying: String(describing: error))
        }

        guard case .object(var dict) = root, let schemaField = dict["schema"]?.stringValue else {
            try? backUp(url: url)
            throw DocumentStoreError.corrupt(underlying: "missing or malformed \"schema\" field")
        }

        let components = schemaField.split(separator: "/", maxSplits: 1)
        guard components.count == 2, let foundVersion = Int(components[1]) else {
            try? backUp(url: url)
            throw DocumentStoreError.corrupt(underlying: "unparsable schema id \"\(schemaField)\"")
        }
        let foundName = String(components[0])
        guard foundName == schemaName else {
            throw DocumentStoreError.schemaNameMismatch(expected: schemaName, found: foundName)
        }
        guard foundVersion <= schemaVersion else {
            try? backUp(url: url)
            throw DocumentStoreError.newerSchema(name: schemaName, found: foundVersion, supported: schemaVersion)
        }

        dict.removeValue(forKey: "schema")
        var payload = JSONValue.object(dict)
        var version = foundVersion
        let byFromVersion = Dictionary(uniqueKeysWithValues: migrations.map { ($0.fromVersion, $0) })
        while version < schemaVersion, let migration = byFromVersion[version] {
            payload = migration.apply(payload)
            version += 1
        }

        return try payload.decode(T.self)
    }

    /// Encodes `value` (which must encode to a JSON object) wrapped in `{ "schema": "<name>/<version>", ... }`
    /// and writes it atomically.
    public func save<T: Encodable & Sendable>(
        _ value: T,
        relativePath: String,
        schemaName: String,
        schemaVersion: Int
    ) throws {
        let encoded = try JSONValue.from(encodable: value)
        guard case .object(var dict) = encoded else {
            throw DocumentStoreError.corrupt(underlying: "value does not encode to a JSON object")
        }
        dict["schema"] = .string("\(schemaName)/\(schemaVersion)")

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let url = baseDirectory.appendingPathComponent(relativePath)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(JSONValue.object(dict))
        try data.write(to: url, options: .atomic)
    }

    private func backUp(url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let timestamp = Int(Date().timeIntervalSince1970)
        let backupURL = url.appendingPathExtension("bak-\(timestamp)")
        try? fileManager.removeItem(at: backupURL)
        try fileManager.copyItem(at: url, to: backupURL)
    }
}
