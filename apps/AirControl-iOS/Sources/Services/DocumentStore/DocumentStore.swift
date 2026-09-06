// Services/DocumentStore/DocumentStore.swift
// Codable JSON document store per arch §6.3: atomic writes under
// `Application Support/AirControl/`, a versioned envelope (`{ "schema": "<name>/<int>", ... }`),
// and a migration hook. Concrete documents (e.g. `TrustedHosts.json`, macro caches) are owned by
// whichever feature/agent defines their payload types (Devices/Pairing, Macros); this module only
// owns the generic store and its migration/versioning policy.
//
// Migration policy (arch §6.3): migrators are pure functions `(JSONObject, fromVersion) ->
// JSONObject` registered per schema and applied in sequence. A document with a newer schema than
// the app knows is not loaded — it is backed up to `<name>.json.bak-<timestamp>` and the caller
// receives defaults. A corrupt document is backed up the same way and replaced by defaults.

import Foundation

/// A JSON object as decoded by `JSONSerialization` — the representation migrations operate on,
/// since a migration may need to add/rename/remove fields that don't yet exist in any `Codable`
/// type the app compiles.
public typealias JSONObject = [String: Any]

/// A pure migration step: transforms a document's JSON object one schema version forward.
public typealias DocumentMigration = @Sendable (JSONObject) -> JSONObject

/// Describes one JSON document.
public struct DocumentDescriptor<T: Codable & Sendable>: Sendable {
    /// Path relative to the store's root directory (`Application Support/AirControl/`), e.g.
    /// `"TrustedHosts.json"` or `"Macros/\(hostID).json"`.
    public let relativePath: String
    /// Schema name (arch §6.3's `"<name>"` in `"<name>/<int>"`), e.g. `"trusted-hosts"`.
    public let schemaName: String
    /// Current schema version this build understands.
    public let currentVersion: Int
    public let defaultValue: @Sendable () -> T
    /// Keyed by the version being migrated *from*; each closure returns the document advanced to
    /// `version + 1`. Not required to cover every prior version if callers only ever ship
    /// sequential migrations, but `load` will fall back to defaults if a hop is missing.
    public let migrations: [Int: DocumentMigration]

    public init(
        relativePath: String,
        schemaName: String,
        currentVersion: Int,
        defaultValue: @escaping @Sendable () -> T,
        migrations: [Int: DocumentMigration] = [:]
    ) {
        self.relativePath = relativePath
        self.schemaName = schemaName
        self.currentVersion = currentVersion
        self.defaultValue = defaultValue
        self.migrations = migrations
    }
}

public enum DocumentStoreError: Error, Sendable {
    case encodingFailed
    case decodingFailed
}

/// Actor-isolated JSON document store. One instance is shared app-wide via `AppEnvironment`.
public actor DocumentStore {
    private let rootDirectory: URL
    private let fileManager: FileManager = .default

    /// - Parameter rootDirectory: Defaults to `Application Support/AirControl/` in the app's
    ///   container. Tests pass a temporary directory.
    public init(rootDirectory: URL? = nil) {
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.rootDirectory = appSupport.appendingPathComponent("AirControl", isDirectory: true)
        }
    }

    /// Loads `descriptor`'s document, migrating forward as needed. Returns `defaultValue()` if
    /// the file is absent, corrupt, from a newer schema than this build knows, or missing a
    /// migration hop — corrupt/too-new files are preserved as a timestamped `.bak` copy.
    public func load<T: Codable & Sendable>(_ descriptor: DocumentDescriptor<T>) -> T {
        let url = rootDirectory.appendingPathComponent(descriptor.relativePath)
        guard let data = try? Data(contentsOf: url) else {
            return descriptor.defaultValue()
        }
        guard let rawObject = try? JSONSerialization.jsonObject(with: data),
              var json = rawObject as? JSONObject else {
            backupCorrupt(url)
            return descriptor.defaultValue()
        }
        guard let schemaString = json["schema"] as? String,
              let (name, version) = Self.parseSchema(schemaString),
              name == descriptor.schemaName else {
            backupCorrupt(url)
            return descriptor.defaultValue()
        }
        if version > descriptor.currentVersion {
            // Newer than this build understands — do not attempt to read it (arch §6.3).
            backupCorrupt(url)
            return descriptor.defaultValue()
        }
        var currentVersion = version
        while currentVersion < descriptor.currentVersion {
            guard let migrate = descriptor.migrations[currentVersion] else {
                backupCorrupt(url)
                return descriptor.defaultValue()
            }
            json = migrate(json)
            currentVersion += 1
        }
        json["schema"] = "\(descriptor.schemaName)/\(descriptor.currentVersion)"
        guard let finalData = try? JSONSerialization.data(withJSONObject: json),
              let decoded = try? JSONDecoder().decode(T.self, from: finalData) else {
            backupCorrupt(url)
            return descriptor.defaultValue()
        }
        return decoded
    }

    /// Encodes `value`, stamps the current schema envelope field, and writes atomically with
    /// `.completeUntilFirstUserAuthentication` file protection (arch §6.3).
    public func save<T: Codable & Sendable>(_ value: T, descriptor: DocumentDescriptor<T>) throws {
        let encoded = try JSONEncoder().encode(value)
        guard let rawObject = try? JSONSerialization.jsonObject(with: encoded),
              var json = rawObject as? JSONObject else {
            throw DocumentStoreError.encodingFailed
        }
        json["schema"] = "\(descriptor.schemaName)/\(descriptor.currentVersion)"
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])

        let url = rootDirectory.appendingPathComponent(descriptor.relativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try? fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
    }

    /// Removes a document entirely (e.g. Forget deleting a host's macro cache).
    public func delete(relativePath: String) throws {
        let url = rootDirectory.appendingPathComponent(relativePath)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func backupCorrupt(_ url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let timestamp = Int(Date().timeIntervalSince1970)
        let backupURL = url.deletingPathExtension().appendingPathExtension("json.bak-\(timestamp)")
        try? fileManager.moveItem(at: url, to: backupURL)
    }

    private static func parseSchema(_ schema: String) -> (name: String, version: Int)? {
        guard let slashIndex = schema.lastIndex(of: "/") else { return nil }
        let name = String(schema[schema.startIndex..<slashIndex])
        guard let version = Int(schema[schema.index(after: slashIndex)...]) else { return nil }
        return (name, version)
    }
}
