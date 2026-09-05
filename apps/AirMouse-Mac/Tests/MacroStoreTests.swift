// Tests for `MacroStore` (spec §5.5.2 storage/starter set/import-export, §5.5.1 validation/limits).
import Testing
@testable import Air_Mouse
import AirMouseProtocol
import Foundation

@Suite struct MacroStoreTests {
    private func makeStore() -> (MacroStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (MacroStore(documentStore: DocumentStore(baseDirectory: dir)), dir)
    }

    private func sampleMacro(name: String, page: Int = 1, order: Int = 0) -> Macro {
        Macro(
            name: name,
            icon: "star.fill",
            action: .keyCombo(modifiers: [.command], keyCode: VirtualKey.kVK_ANSI_A, keyLabel: "⌘A"),
            page: page,
            order: order
        )
    }

    @Test func firstRunSeedsTheStarterSet() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let macros = await store.list()
        #expect(macros.count == 8)
        #expect(macros.contains { $0.name == "Mission Control" })
        #expect(macros.contains { $0.name == "Terminal" && $0.action == .launchApp(bundleID: "com.apple.Terminal", activateIfRunning: true) })
        #expect(await store.revision == 1)
    }

    @Test func createUpdateDeleteRoundTripAndBumpRevision() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = await store.list() // bootstrap
        let startRevision = await store.revision

        let macro = sampleMacro(name: "Custom One")
        try await store.create(macro)
        #expect(await store.revision == startRevision + 1)
        #expect(await store.macro(id: macro.id)?.name == "Custom One")

        var updated = macro
        updated.name = "Renamed"
        try await store.update(updated)
        #expect(await store.macro(id: macro.id)?.name == "Renamed")
        #expect(await store.revision == startRevision + 2)

        try await store.delete(id: macro.id)
        #expect(await store.macro(id: macro.id) == nil)
        #expect(await store.revision == startRevision + 3)
    }

    @Test func updatingAMissingMacroThrowsNotFound() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = await store.list()

        let ghost = sampleMacro(name: "Ghost")
        await #expect(throws: MacroStoreError.notFound(id: ghost.id)) {
            try await store.update(ghost)
        }
    }

    @Test func exceedingTheSixtyFourMacroLimitThrows() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = await store.list() // 8 starter macros already exist

        // Fill pages 1-5 up to the 12-per-page cap (spread across pages so the per-page limit isn't
        // hit before the total limit) to reach 64 total, then one more must fail.
        var count = 8
        pageLoop: for page in 1..<ProtocolConstants.macroMaxPages {
            for order in 0..<ProtocolConstants.macroMaxPerPage {
                guard count < ProtocolConstants.macroMaxTotal else { break pageLoop }
                try await store.create(sampleMacro(name: "M\(count)", page: page, order: order))
                count += 1
            }
        }
        #expect(await store.list().count == ProtocolConstants.macroMaxTotal)

        await #expect(throws: (any Error).self) {
            try await store.create(sampleMacro(name: "Overflow", page: 0, order: 99))
        }
    }

    @Test func duplicateNamesAreRejected() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = await store.list()

        try await store.create(sampleMacro(name: "Unique Name"))
        await #expect(throws: (any Error).self) {
            try await store.create(sampleMacro(name: "unique name")) // case-insensitive collision
        }
    }

    @Test func duplicateInsertsACopyWithAUniqueName() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = await store.list()

        let macro = sampleMacro(name: "Original")
        try await store.create(macro)
        let copy = try await store.duplicate(id: macro.id)

        #expect(copy.id != macro.id)
        #expect(copy.name == "Original copy")
        #expect(await store.list().contains { $0.id == copy.id })
    }

    @Test func importedScriptMacrosAreForcedToRequireConfirmation() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = await store.list()

        let scriptMacro = Macro(
            name: "Deploy",
            icon: "hammer.fill",
            action: .shellCommand(command: "echo hi"),
            page: 2,
            order: 0
        )
        #expect(scriptMacro.requiresConfirmation) // forced true at construction already (spec §5.5.1)

        let importDoc = MacroDocument(revision: 1, macros: [scriptMacro])
        let data = try JSONEncoder().encode(importDoc)

        let preview = try await store.previewImport(data: data)
        #expect(preview.scriptCount == 1)
        #expect(preview.resultingMacros.first(where: { $0.id == scriptMacro.id })?.requiresConfirmation == true)

        try await store.applyImport(preview)
        let stored = await store.macro(id: scriptMacro.id)
        #expect(stored?.requiresConfirmation == true)
        #expect(stored?.isScript == true)
    }

    @Test func importMergesByIDAndReportsReplacedCount() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = await store.list()

        let original = sampleMacro(name: "Keep Me")
        try await store.create(original)

        var replacement = original
        replacement.name = "Replaced"
        let importDoc = MacroDocument(revision: 5, macros: [replacement])
        let data = try JSONEncoder().encode(importDoc)

        let preview = try await store.previewImport(data: data)
        #expect(preview.importedCount == 1)
        #expect(preview.replacedCount == 1)

        try await store.applyImport(preview)
        #expect(await store.macro(id: original.id)?.name == "Replaced")
    }

    @Test func importWithWrongSchemaNameThrows() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = await store.list()

        let badJSON = Data(#"{"schema": "not-macros/1", "revision": 1, "macros": []}"#.utf8)
        await #expect(throws: MacroStoreError.self) {
            _ = try await store.previewImport(data: badJSON)
        }
    }

    @Test func exportProducesADecodableMacroDocument() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = await store.list()

        let data = try await store.exportDocument()
        let decoded = try JSONDecoder().decode(MacroDocument.self, from: data)
        #expect(decoded.schema == MacroDocument.schemaName)
        #expect(decoded.macros.count == 8)
    }

    @Test func changesStreamYieldsOnEveryMutation() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = await store.list()

        let stream = await store.changes()
        var iterator = stream.makeAsyncIterator()

        let macro = sampleMacro(name: "Streamed")
        try await store.create(macro)

        let list = await iterator.next()
        #expect(list?.macros.contains { $0.id == macro.id } == true)
    }

    @Test func replaceAllRejectsAnInvalidList() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let existing = await store.list()

        var tooMany = existing
        for index in 0..<ProtocolConstants.macroMaxTotal {
            tooMany.append(sampleMacro(name: "Extra \(index)", page: 5, order: index))
        }
        await #expect(throws: (any Error).self) {
            try await store.replaceAll(tooMany)
        }
    }
}
