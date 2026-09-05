import Testing
@testable import Air_Mouse
import Foundation

@Suite struct DocumentStoreTests {
    private struct Widget: Codable, Sendable, Equatable {
        var name: String
        var count: Int
    }

    private func makeStore() -> (DocumentStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (DocumentStore(baseDirectory: dir), dir)
    }

    @Test func roundTripsAValueThroughTheSchemaEnvelope() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let widget = Widget(name: "gadget", count: 3)
        try await store.save(widget, relativePath: "Widget.json", schemaName: "widget", schemaVersion: 1)

        let loaded = try await store.load(Widget.self, relativePath: "Widget.json", schemaName: "widget", schemaVersion: 1)
        #expect(loaded == widget)
    }

    @Test func missingFileReturnsNilRatherThanThrowing() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let loaded = try await store.load(Widget.self, relativePath: "Nope.json", schemaName: "widget", schemaVersion: 1)
        #expect(loaded == nil)
    }

    @Test func migratesForwardThroughRegisteredSteps() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Write a v1 document by hand (as if written by an older build).
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let v1Data = try JSONSerialization.data(withJSONObject: ["schema": "widget/1", "name": "gadget"])
        try v1Data.write(to: dir.appendingPathComponent("Widget.json"))

        let migration = DocumentStore.Migration(fromVersion: 1) { value in
            guard case .object(var dict) = value else { return value }
            dict["count"] = .number(0)
            return .object(dict)
        }

        let loaded = try await store.load(
            Widget.self,
            relativePath: "Widget.json",
            schemaName: "widget",
            schemaVersion: 2,
            migrations: [migration]
        )
        #expect(loaded == Widget(name: "gadget", count: 0))
    }

    @Test func newerSchemaIsBackedUpAndThrows() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let futureData = try JSONSerialization.data(withJSONObject: ["schema": "widget/99", "name": "gadget", "count": 1])
        let fileURL = dir.appendingPathComponent("Widget.json")
        try futureData.write(to: fileURL)

        await #expect(throws: DocumentStoreError.self) {
            _ = try await store.load(Widget.self, relativePath: "Widget.json", schemaName: "widget", schemaVersion: 1)
        }

        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains(".bak-") }
        #expect(!backups.isEmpty)
    }
}
