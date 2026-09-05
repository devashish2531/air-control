// Tests/DocumentStoreTests.swift
// Round trip, migration, and corrupt/newer-schema handling for `DocumentStore` (arch §6.3).

import Testing
import Foundation
@testable import Air_Mouse

private struct SampleDocumentV2: Codable, Sendable, Equatable {
    var name: String
    var count: Int
}

@Suite struct DocumentStoreTests {
    private func makeStore() -> (DocumentStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DocumentStoreTests-\(UUID().uuidString)")
        return (DocumentStore(rootDirectory: root), root)
    }

    private func descriptor(currentVersion: Int = 2) -> DocumentDescriptor<SampleDocumentV2> {
        DocumentDescriptor(
            relativePath: "Sample.json",
            schemaName: "sample",
            currentVersion: currentVersion,
            defaultValue: { SampleDocumentV2(name: "default", count: 0) },
            migrations: [
                // v1 -> v2: "count" was introduced with a default of 0.
                1: { json in
                    var json = json
                    if json["count"] == nil {
                        json["count"] = 0
                    }
                    return json
                }
            ]
        )
    }

    @Test func loadMissingReturnsDefault() async {
        let (store, _) = makeStore()
        let loaded = await store.load(descriptor())
        #expect(loaded == SampleDocumentV2(name: "default", count: 0))
    }

    @Test func saveThenLoadRoundTrips() async throws {
        let (store, _) = makeStore()
        let value = SampleDocumentV2(name: "Living Room Mac", count: 3)
        try await store.save(value, descriptor: descriptor())
        let loaded = await store.load(descriptor())
        #expect(loaded == value)
    }

    @Test func envelopeCarriesSchemaNameAndVersion() async throws {
        let (store, root) = makeStore()
        try await store.save(SampleDocumentV2(name: "x", count: 1), descriptor: descriptor())
        let data = try Data(contentsOf: root.appendingPathComponent("Sample.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["schema"] as? String == "sample/2")
    }

    @Test func migratesForwardFromOlderVersion() async throws {
        let (store, root) = makeStore()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let v1JSON: [String: Any] = ["schema": "sample/1", "name": "Old Doc"]
        let data = try JSONSerialization.data(withJSONObject: v1JSON)
        try data.write(to: root.appendingPathComponent("Sample.json"))

        let loaded = await store.load(descriptor())
        #expect(loaded == SampleDocumentV2(name: "Old Doc", count: 0))
    }

    @Test func newerSchemaThanKnownFallsBackToDefaultsAndBacksUp() async throws {
        let (store, root) = makeStore()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let futureJSON: [String: Any] = ["schema": "sample/99", "name": "From the future", "count": 1]
        let data = try JSONSerialization.data(withJSONObject: futureJSON)
        let url = root.appendingPathComponent("Sample.json")
        try data.write(to: url)

        let loaded = await store.load(descriptor())
        #expect(loaded == SampleDocumentV2(name: "default", count: 0))

        // Original file preserved as a timestamped backup, not deleted.
        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(remaining.contains { $0.hasPrefix("Sample.json.bak-") })
    }

    @Test func corruptJSONFallsBackToDefaultsAndBacksUp() async throws {
        let (store, root) = makeStore()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("Sample.json")
        try Data("{ not valid json".utf8).write(to: url)

        let loaded = await store.load(descriptor())
        #expect(loaded == SampleDocumentV2(name: "default", count: 0))
        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(remaining.contains { $0.hasPrefix("Sample.json.bak-") })
    }

    @Test func missingMigrationHopFallsBackToDefaults() async throws {
        let (store, root) = makeStore()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Schema claims v0, but no migration is registered for version 0.
        let v0JSON: [String: Any] = ["schema": "sample/0", "name": "Ancient"]
        let data = try JSONSerialization.data(withJSONObject: v0JSON)
        try data.write(to: root.appendingPathComponent("Sample.json"))

        let loaded = await store.load(descriptor())
        #expect(loaded == SampleDocumentV2(name: "default", count: 0))
    }

    @Test func deleteRemovesDocument() async throws {
        let (store, root) = makeStore()
        try await store.save(SampleDocumentV2(name: "x", count: 1), descriptor: descriptor())
        try await store.delete(relativePath: "Sample.json")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Sample.json").path))
    }
}
