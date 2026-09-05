// spec §5.5.3 Editor UI + §5.5.2 import/export + "Test" button (assignment brief, exercised through the
// same `MacroEngine` gating a real `macroInvoke` would go through — spec §5.5.5).
import AirMouseProtocol
import Foundation
import Observation

@MainActor
@Observable
final class MacroEditorViewModel {
    private let store: any MacroStoreProviding
    private let engine: MacroEngine
    /// Read for the script-editor warning banner and to gate the local "Test" button the same way a
    /// real device would be gated by the *global* half of spec §5.5.5's three-way check (the per-device
    /// half doesn't apply to a same-machine test — see `test(_:)`).
    var allowScriptsGlobal: Bool

    private(set) var macros: [Macro] = []
    var selectedPage: Int = 0

    var editingDraft: MacroDraft?
    var isCreatingNew = false
    var errorMessage: String?
    var testResultMessage: String?

    var pendingDeleteID: UUID?
    var pendingImportPreview: MacroImportPreview?
    var importError: String?

    init(store: any MacroStoreProviding, engine: MacroEngine, allowScriptsGlobal: Bool) {
        self.store = store
        self.engine = engine
        self.allowScriptsGlobal = allowScriptsGlobal
    }

    func refresh() async {
        macros = await store.list()
    }

    func macros(onPage page: Int) -> [Macro] {
        macros.filter { $0.page == page }.sorted { $0.order < $1.order }
    }

    var pendingDeleteName: String? {
        guard let id = pendingDeleteID else { return nil }
        return macros.first(where: { $0.id == id })?.name
    }

    // MARK: Create / edit

    func startCreating() {
        let existingOnPage = macros(onPage: selectedPage).count
        guard existingOnPage < ProtocolConstants.macroMaxPerPage, macros.count < ProtocolConstants.macroMaxTotal else {
            errorMessage = existingOnPage >= ProtocolConstants.macroMaxPerPage
                ? "This page already has \(ProtocolConstants.macroMaxPerPage) macros."
                : "You already have \(ProtocolConstants.macroMaxTotal) macros, the maximum."
            return
        }
        isCreatingNew = true
        editingDraft = .new(page: selectedPage, order: existingOnPage)
    }

    func startEditing(_ macro: Macro) {
        isCreatingNew = false
        editingDraft = MacroDraft(macro: macro)
    }

    func cancelEditing() {
        editingDraft = nil
        isCreatingNew = false
    }

    func saveDraft() async {
        guard let draft = editingDraft else { return }
        guard let macro = draft.makeMacro() else {
            errorMessage = "This macro isn't fully configured yet."
            return
        }
        do {
            if isCreatingNew {
                try await store.create(macro)
            } else {
                try await store.update(macro)
            }
            await refresh()
            editingDraft = nil
            isCreatingNew = false
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    // MARK: Duplicate / delete

    func duplicate(_ id: UUID) async {
        do {
            try await store.duplicate(id: id)
            await refresh()
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func requestDelete(_ id: UUID) {
        pendingDeleteID = id
    }

    func cancelDelete() {
        pendingDeleteID = nil
    }

    func confirmDelete() async {
        guard let id = pendingDeleteID else { return }
        do {
            try await store.delete(id: id)
            await refresh()
        } catch {
            errorMessage = Self.describe(error)
        }
        pendingDeleteID = nil
    }

    // MARK: Reorder (drag within/across pages, spec §5.5.3 "drag to reorder across pages")

    /// Moves `macroID` to `page`, inserting it at `order` among that page's macros, and renumbers every
    /// affected page's `order` values contiguously from 0. Persisted as one `replaceAll` so the whole
    /// move is validated and saved atomically.
    func move(macroID: UUID, toPage page: Int, order: Int) async {
        guard var moved = macros.first(where: { $0.id == macroID }) else { return }
        var remaining = macros.filter { $0.id != macroID }
        moved.page = page

        var destination = remaining.filter { $0.page == page }.sorted { $0.order < $1.order }
        let insertionIndex = min(max(order, 0), destination.count)
        destination.insert(moved, at: insertionIndex)
        for index in destination.indices { destination[index].order = index }

        remaining.removeAll { $0.page == page }
        remaining.append(contentsOf: destination)

        do {
            try await store.replaceAll(remaining)
            await refresh()
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    // MARK: Test (assignment: "'Test' button that invokes via `MacroEngine` locally")

    func test(_ macro: Macro) async {
        // Local test run by the person editing the macro on this very Mac: `confirmed: true` and
        // `deviceAllowsScripts: true` are supplied unconditionally (there is no remote "device" to ask —
        // the operator sitting at the Mac already implicitly trusts themselves), but the *global*
        // Preferences › Security toggle still gates script kinds exactly as it would for a real
        // `macroInvoke` (spec §5.5.5) — testing does not bypass the policy the user set.
        let invoke = MacroInvoke(id: macro.id, confirmed: true)
        let result = await engine.invoke(
            invoke,
            from: "local-test",
            deviceAllowsScripts: true,
            globalScriptsEnabled: allowScriptsGlobal
        )
        testResultMessage = Self.describeResult(result, macroName: macro.name)
    }

    private static func describeResult(_ result: MacroResult, macroName: String) -> String {
        // spec §9 error-copy table, adapted for a local test (no toast/host round trip involved).
        switch result.code {
        case .ok:
            "\(macroName) ran."
        case .blockedByPolicy:
            "Blocked by Mac policy"
        case .confirmationRequired:
            "Confirmation required"
        case .timeout:
            "\(macroName) timed out"
        case .failed:
            "\(macroName) failed: \(result.message)"
        case .notFound:
            "That macro was removed on the Mac"
        }
    }

    // MARK: Import / export (spec §5.5.2)

    func previewImport(data: Data) async {
        do {
            pendingImportPreview = try await store.previewImport(data: data)
            importError = nil
        } catch {
            importError = Self.describe(error)
            pendingImportPreview = nil
        }
    }

    func confirmImport() async {
        guard let preview = pendingImportPreview else { return }
        do {
            try await store.applyImport(preview)
            await refresh()
        } catch {
            importError = Self.describe(error)
        }
        pendingImportPreview = nil
    }

    func cancelImport() {
        pendingImportPreview = nil
        importError = nil
    }

    func exportData() async -> Data? {
        do {
            return try await store.exportDocument()
        } catch {
            errorMessage = Self.describe(error)
            return nil
        }
    }

    private static func describe(_ error: Error) -> String {
        if let described = error as? LocalizedError, let message = described.errorDescription {
            return message
        }
        return String(describing: error)
    }
}
