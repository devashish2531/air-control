// spec §5.5.2 "Storage, defaults, export/import" + §5.5.6 "Sync" + arch §3.3 "`MacroEngine` (actor)"
// row's `MacroStore + validation + sync`. Persists through the shell's `DocumentStore`
// (Support/DocumentStore.swift) rather than doing its own file I/O, so schema envelope, atomic writes,
// and the newer-schema/corrupt-file backup policy (arch §6.3) are shared with every other document.
import AirMouseProtocol
import Foundation

/// Richer surface than the shell's `MacroStoring` (`App/ServiceProtocols.swift`, which only exposes
/// `macroCount` for the menu). Defined in this module per CLAUDE.md ("extend via a richer protocol
/// `MacroStoreProviding` in your directory if you need more than `macroCount`") so the Macro editor and
/// `MacroEngine` have a real CRUD/sync surface while the shell's DI slot stays tiny.
public protocol MacroStoreProviding: MacroStoring {
    /// Current revision (spec §5.5.2: "`revision` incremented on every save").
    var revision: Int { get async }
    func list() async -> [Macro]
    func macro(id: UUID) async -> Macro?

    /// Validates `macro` against the *other* macros already stored (uniqueness, per-page/total limits —
    /// `MacroValidator.validate(all:)`), appends it, bumps `revision`, persists, and broadcasts to
    /// `changes()`.
    func create(_ macro: Macro) async throws
    /// Replaces the macro with the same `id`; throws `MacroStoreError.notFound` if it isn't present.
    func update(_ macro: Macro) async throws
    func delete(id: UUID) async throws
    /// Duplicates `id` with a new `UUID`, a name suffixed to stay unique, and placed immediately after
    /// the original (spec §5.5.3 editor "duplicate" — not itself normative wire behavior, just the
    /// editor's copy affordance).
    @discardableResult
    func duplicate(id: UUID) async throws -> Macro
    /// Bulk replace used by drag reorder (which can touch many macros' `page`/`order` at once) and by
    /// the import merge. Validates the *entire* incoming list with `MacroValidator.validate(all:)`
    /// before committing anything.
    func replaceAll(_ macros: [Macro]) async throws

    /// spec §5.5.2 Import: "validates the schema, merges by `id` (imported wins; `updatedAt` refreshed),
    /// enforces limits, and previews the count before applying. Script macros in an import are imported
    /// **disabled**." `preview` is exposed as a separate step so the editor can show the "N macros will
    /// be imported" confirmation before `apply` commits.
    func previewImport(data: Data) async throws -> MacroImportPreview
    func applyImport(_ preview: MacroImportPreview) async throws
    /// spec §5.5.2 Export: "writes the same document via `NSSavePanel`" — this returns the bytes; the
    /// editor is responsible for the save panel itself.
    func exportDocument() async throws -> Data

    /// spec §5.5.6 "On every save the host bumps `revision` and sends `macroList` to all authenticated
    /// sessions." The networking layer (not owned here) should subscribe once and forward each element
    /// to `SessionManager`. Multiple independent subscribers are supported; each gets every update from
    /// the moment it subscribes.
    func changes() async -> AsyncStream<MacroList>
}

/// One macro-import attempt, already parsed and validated against the limits, but not yet committed
/// (spec §5.5.2: "previews the count before applying").
public struct MacroImportPreview: Sendable, Equatable {
    /// The full macro list that would result if applied (existing macros not present in the import,
    /// plus the imported ones — imported wins on `id` collision).
    public var resultingMacros: [Macro]
    public var importedCount: Int
    public var replacedCount: Int
    public var scriptCount: Int
}

public enum MacroStoreError: Error, Sendable, Equatable {
    case notFound(id: UUID)
    case importSchemaMismatch(found: String)
    case importDecodeFailed(String)
}

/// The host-side `MacroStore` (arch §3.3's `MX` node). One instance per app; owns `Macros.json` and the
/// in-memory `MacroDocument`, all mutation serialized by actor isolation.
public actor MacroStore: MacroStoreProviding {
    private static let relativePath = "Macros.json"
    private static let schemaVersion = 1
    /// `DocumentStore` composes `"<name>/<version>"` itself; `MacroDocument.schemaName` ("macros/1") already
    /// carries the version, so pass only the name or the file is written as "macros/1/1" and never loads again.
    private static let documentSchemaName = String(MacroDocument.schemaName.split(separator: "/").first ?? "macros")

    private let documentStore: DocumentStore
    private var document: MacroDocument
    private var continuations: [UUID: AsyncStream<MacroList>.Continuation] = [:]
    private var didBootstrap = false

    public init(documentStore: DocumentStore) {
        self.documentStore = documentStore
        self.document = MacroDocument(revision: 0, macros: [])
    }

    // MARK: MacroStoring (shell's tiny DI slot)

    public var macroCount: Int {
        get async {
            await ensureBootstrapped()
            return document.macros.count
        }
    }

    // MARK: MacroStoreProviding

    public var revision: Int {
        get async {
            await ensureBootstrapped()
            return document.revision
        }
    }

    public func list() async -> [Macro] {
        await ensureBootstrapped()
        return document.macros
    }

    public func macro(id: UUID) async -> Macro? {
        await ensureBootstrapped()
        return document.macros.first { $0.id == id }
    }

    public func create(_ macro: Macro) async throws {
        await ensureBootstrapped()
        var updated = document.macros
        updated.append(macro)
        try MacroValidator.validate(all: updated)
        try await commit(updated)
    }

    public func update(_ macro: Macro) async throws {
        await ensureBootstrapped()
        var updated = document.macros
        guard let index = updated.firstIndex(where: { $0.id == macro.id }) else {
            throw MacroStoreError.notFound(id: macro.id)
        }
        var revised = macro
        revised.updatedAt = Date()
        updated[index] = revised
        try MacroValidator.validate(all: updated)
        try await commit(updated)
    }

    public func delete(id: UUID) async throws {
        await ensureBootstrapped()
        var updated = document.macros
        guard let index = updated.firstIndex(where: { $0.id == id }) else {
            throw MacroStoreError.notFound(id: id)
        }
        updated.remove(at: index)
        try await commit(updated)
    }

    @discardableResult
    public func duplicate(id: UUID) async throws -> Macro {
        await ensureBootstrapped()
        guard let original = document.macros.first(where: { $0.id == id }) else {
            throw MacroStoreError.notFound(id: id)
        }
        let existingNames = Set(document.macros.map { $0.name.lowercased() })
        var candidateName = "\(original.name) copy"
        var suffix = 2
        while existingNames.contains(candidateName.lowercased()) {
            candidateName = "\(original.name) copy \(suffix)"
            suffix += 1
        }
        candidateName = String(candidateName.prefix(ProtocolConstants.macroNameMaxLength))

        var copy = original
        copy.id = UUID()
        copy.name = candidateName
        copy.order = original.order + 1
        copy.createdAt = Date()
        copy.updatedAt = Date()

        var updated = document.macros
        if let originalIndex = updated.firstIndex(where: { $0.id == id }) {
            updated.insert(copy, at: originalIndex + 1)
        } else {
            updated.append(copy)
        }
        try MacroValidator.validate(all: updated)
        try await commit(updated)
        return copy
    }

    public func replaceAll(_ macros: [Macro]) async throws {
        await ensureBootstrapped()
        try MacroValidator.validate(all: macros)
        try await commit(macros)
    }

    public func previewImport(data: Data) async throws -> MacroImportPreview {
        await ensureBootstrapped()
        let decoder = JSONDecoder()
        let decoded: MacroDocument
        do {
            decoded = try decoder.decode(MacroDocument.self, from: data)
        } catch {
            throw MacroStoreError.importDecodeFailed(String(describing: error))
        }
        guard decoded.schema == MacroDocument.schemaName else {
            throw MacroStoreError.importSchemaMismatch(found: decoded.schema)
        }

        // spec §5.5.2: "Script macros in an import are imported **disabled**" — force
        // `requiresConfirmation = true` (already true for script kinds by construction) and, per
        // §7.2 "imports never enable scripts" (decisions Addendum A9), there is no separate "enabled"
        // flag to clear here: script execution is gated at invoke time by the *global* and *per-device*
        // policy toggles (§5.5.5), which an import can never touch. Re-round-tripping through `Macro`'s
        // memberwise fields (rather than just `Codable`) keeps that guarantee even if a hand-edited
        // import file tried to set `requiresConfirmation: false` on a script macro.
        let importedMacros = decoded.macros.map { macro -> Macro in
            Macro(
                id: macro.id,
                name: macro.name,
                icon: macro.icon,
                tint: macro.tint,
                action: macro.action,
                page: macro.page,
                order: macro.order,
                showOnMediaPage: macro.showOnMediaPage,
                requiresConfirmation: macro.requiresConfirmation,
                createdAt: macro.createdAt,
                updatedAt: Date()
            )
        }

        let existingByID = Dictionary(uniqueKeysWithValues: document.macros.map { ($0.id, $0) })
        var resulting = document.macros
        var replacedCount = 0
        for imported in importedMacros {
            if let index = resulting.firstIndex(where: { $0.id == imported.id }) {
                resulting[index] = imported
                replacedCount += 1
            } else {
                resulting.append(imported)
            }
        }
        try MacroValidator.validate(all: resulting)

        return MacroImportPreview(
            resultingMacros: resulting,
            importedCount: importedMacros.count,
            replacedCount: existingByID.isEmpty ? 0 : replacedCount,
            scriptCount: importedMacros.filter(\.isScript).count
        )
    }

    public func applyImport(_ preview: MacroImportPreview) async throws {
        try await commit(preview.resultingMacros)
    }

    public func exportDocument() async throws -> Data {
        await ensureBootstrapped()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    public func changes() async -> AsyncStream<MacroList> {
        let token = UUID()
        return AsyncStream { continuation in
            continuations[token] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(token) }
            }
        }
    }

    // MARK: Bootstrap (spec §5.5.2 starter set)

    /// Loads `Macros.json`, or seeds the FR-MC-010 starter set on first run. Idempotent and safe to call
    /// from every public entry point instead of requiring callers to `await` a separate `start()` first.
    private func ensureBootstrapped() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        do {
            if let loaded = try await documentStore.load(
                MacroDocument.self,
                relativePath: Self.relativePath,
                schemaName: Self.documentSchemaName,
                schemaVersion: Self.schemaVersion
            ) {
                document = loaded
                return
            }
        } catch {
            Log.store.error("Failed to load Macros.json, starting fresh: \(String(describing: error), privacy: .public)")
        }
        document = MacroDocument(revision: 1, macros: Self.starterSet())
        try? await persist()
    }

    private func commit(_ macros: [Macro]) async throws {
        document.macros = macros
        document.revision += 1
        try await persist()
        broadcast()
    }

    private func persist() async throws {
        try await documentStore.save(
            document,
            relativePath: Self.relativePath,
            schemaName: Self.documentSchemaName,
            schemaVersion: Self.schemaVersion
        )
    }

    private func broadcast() {
        let snapshot = MacroList(revision: document.revision, macros: document.macros)
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    private func removeContinuation(_ token: UUID) {
        continuations.removeValue(forKey: token)
    }

    // MARK: Starter set (spec §5.5.2 / FR-MC-010)

    /// "Mission Control (⌃↑), Show Desktop (fn F11), Screenshot (⌘⇧4), Lock Screen (⌃⌘Q), Spotlight
    /// (⌘Space), Terminal (`com.apple.Terminal`), Safari (`com.apple.Safari`), Music (`com.apple.Music`)."
    static func starterSet() -> [Macro] {
        let now = Date()
        func combo(name: String, icon: String, tint: MacroTint, modifiers: KeyModifiers, keyCode: UInt16, keyLabel: String, order: Int) -> Macro {
            Macro(
                name: name,
                icon: icon,
                tint: tint,
                action: .keyCombo(modifiers: modifiers, keyCode: keyCode, keyLabel: keyLabel),
                page: 0,
                order: order,
                createdAt: now,
                updatedAt: now
            )
        }
        func app(name: String, icon: String, tint: MacroTint, bundleID: String, order: Int) -> Macro {
            Macro(
                name: name,
                icon: icon,
                tint: tint,
                action: .launchApp(bundleID: bundleID, activateIfRunning: true),
                page: 0,
                order: order,
                createdAt: now,
                updatedAt: now
            )
        }

        return [
            combo(
                name: "Mission Control", icon: "square.grid.3x3.fill", tint: .blue,
                modifiers: .control, keyCode: VirtualKey.kVK_UpArrow, keyLabel: "⌃↑", order: 0
            ),
            combo(
                name: "Show Desktop", icon: "menubar.dock.rectangle", tint: .teal,
                modifiers: .function, keyCode: VirtualKey.kVK_F11, keyLabel: "fn F11", order: 1
            ),
            combo(
                name: "Screenshot", icon: "camera.viewfinder", tint: .orange,
                modifiers: [.command, .shift], keyCode: VirtualKey.kVK_ANSI_4, keyLabel: "⌘⇧4", order: 2
            ),
            combo(
                name: "Lock Screen", icon: "lock.fill", tint: .red,
                modifiers: [.control, .command], keyCode: VirtualKey.kVK_ANSI_Q, keyLabel: "⌃⌘Q", order: 3
            ),
            combo(
                name: "Spotlight", icon: "magnifyingglass", tint: .purple,
                modifiers: .command, keyCode: VirtualKey.kVK_Space, keyLabel: "⌘Space", order: 4
            ),
            app(name: "Terminal", icon: "terminal.fill", tint: .gray, bundleID: "com.apple.Terminal", order: 5),
            app(name: "Safari", icon: "safari.fill", tint: .cyan, bundleID: "com.apple.Safari", order: 6),
            app(name: "Music", icon: "music.note", tint: .pink, bundleID: "com.apple.Music", order: 7),
        ]
    }
}
