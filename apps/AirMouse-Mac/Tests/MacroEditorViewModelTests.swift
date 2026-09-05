// Tests for `MacroDraft` (form → `MacroAction` conversion/validation) and `MacroEditorViewModel`
// (spec §5.5.3 editor behavior: page/total limits, save/duplicate/delete/reorder, local "Test").
import Testing
@testable import Air_Mouse
import AirMouseProtocol
import Foundation

@Suite struct MacroDraftTests {
    @Test func newDraftHasNoActionUntilAKeyIsRecorded() {
        var draft = MacroDraft.new(page: 0, order: 0)
        #expect(draft.makeAction() == nil)
        draft.comboKeyCode = VirtualKey.kVK_ANSI_A
        draft.comboKeyLabel = "⌘A"
        #expect(draft.makeAction() != nil)
    }

    @Test func keySequenceRequiresAtLeastOneStep() {
        var draft = MacroDraft.new(page: 0, order: 0)
        draft.kind = .keySequence
        #expect(draft.makeAction() == nil)
        draft.sequenceSteps = [.text("hi")]
        #expect(draft.makeAction() != nil)
    }

    @Test func launchAppRequiresANonEmptyBundleID() {
        var draft = MacroDraft.new(page: 0, order: 0)
        draft.kind = .launchApp
        #expect(draft.makeAction() == nil)
        draft.bundleID = "com.apple.Safari"
        #expect(draft.makeAction() == .launchApp(bundleID: "com.apple.Safari", activateIfRunning: true))
    }

    @Test func openURLRequiresAParsableURLWithAScheme() {
        var draft = MacroDraft.new(page: 0, order: 0)
        draft.kind = .openURL
        draft.urlString = "not a url"
        #expect(draft.makeAction() == nil)
        draft.urlString = "https://example.com"
        #expect(draft.makeAction() != nil)
    }

    @Test func scriptKindsAlwaysReportRequiresConfirmationTrue() {
        var draft = MacroDraft.new(page: 0, order: 0)
        draft.kind = .shellCommand
        draft.requiresConfirmationOverride = false
        #expect(draft.requiresConfirmation) // forced true regardless of the (disabled) checkbox

        draft.kind = .keyCombo
        #expect(!draft.requiresConfirmation) // override respected for non-script kinds
    }

    @Test func makeMacroForcesRequiresConfirmationForScriptKinds() {
        var draft = MacroDraft.new(page: 1, order: 0)
        draft.name = "Deploy"
        draft.kind = .shellCommand
        draft.scriptSource = "echo hi"
        let macro = draft.makeMacro()
        #expect(macro?.requiresConfirmation == true)
        #expect(macro?.isScript == true)
    }
}

@MainActor
@Suite struct MacroEditorViewModelTests {
    private func makeViewModel(allowScriptsGlobal: Bool = false) async -> (MacroEditorViewModel, MacroStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = MacroStore(documentStore: DocumentStore(baseDirectory: dir))
        let executor = MockMacroActionExecutor()
        let engine = MacroEngine(store: store, executor: executor)
        let vm = MacroEditorViewModel(store: store, engine: engine, allowScriptsGlobal: allowScriptsGlobal)
        await vm.refresh()
        return (vm, store, dir)
    }

    @Test func startCreatingOpensADraftForTheSelectedPage() async throws {
        let (vm, _, dir) = await makeViewModel()
        defer { try? FileManager.default.removeItem(at: dir) }

        vm.selectedPage = 3
        vm.startCreating()
        #expect(vm.editingDraft?.page == 3)
        #expect(vm.isCreatingNew)
    }

    @Test func startCreatingRefusesPastThePerPageLimit() async throws {
        let (vm, store, dir) = await makeViewModel()
        defer { try? FileManager.default.removeItem(at: dir) }

        vm.selectedPage = 4
        for i in 0..<ProtocolConstants.macroMaxPerPage {
            try await store.create(Macro(
                name: "P4-\(i)",
                icon: "star",
                action: .keyCombo(modifiers: [.command], keyCode: VirtualKey.kVK_ANSI_A, keyLabel: "⌘A"),
                page: 4,
                order: i
            ))
        }
        await vm.refresh()

        vm.startCreating()
        #expect(vm.editingDraft == nil)
        #expect(vm.errorMessage != nil)
    }

    @Test func saveDraftWithoutAValidActionSetsAnErrorInsteadOfSaving() async throws {
        let (vm, _, dir) = await makeViewModel()
        defer { try? FileManager.default.removeItem(at: dir) }

        vm.startCreating() // kind defaults to .keyCombo with no key recorded yet
        vm.editingDraft?.name = "Incomplete"
        await vm.saveDraft()

        #expect(vm.errorMessage != nil)
        #expect(vm.editingDraft != nil) // sheet stays open so the user can finish configuring it
    }

    @Test func saveDraftPersistsAValidNewMacro() async throws {
        let (vm, store, dir) = await makeViewModel()
        defer { try? FileManager.default.removeItem(at: dir) }

        vm.startCreating()
        vm.editingDraft?.name = "New Macro"
        vm.editingDraft?.comboKeyCode = VirtualKey.kVK_ANSI_B
        vm.editingDraft?.comboKeyLabel = "⌘B"
        await vm.saveDraft()

        #expect(vm.editingDraft == nil)
        #expect(vm.errorMessage == nil)
        let stored = await store.list()
        #expect(stored.contains { $0.name == "New Macro" })
    }

    @Test func duplicateAddsACopy() async throws {
        let (vm, store, dir) = await makeViewModel()
        defer { try? FileManager.default.removeItem(at: dir) }

        let before = await store.list().count
        guard let target = await store.list().first else {
            Issue.record("expected starter macros")
            return
        }
        await vm.duplicate(target.id)

        #expect(vm.errorMessage == nil)
        let after = await store.list().count
        #expect(after == before + 1)
    }

    @Test func deleteRequiresConfirmationBeforeRemoving() async throws {
        let (vm, store, dir) = await makeViewModel()
        defer { try? FileManager.default.removeItem(at: dir) }

        guard let target = await store.list().first else {
            Issue.record("expected starter macros")
            return
        }
        vm.requestDelete(target.id)
        #expect(vm.pendingDeleteID == target.id)

        await vm.confirmDelete()
        #expect(await store.macro(id: target.id) == nil)
        #expect(vm.pendingDeleteID == nil)
    }

    @Test func moveReassignsPageAndRenumbersOrder() async throws {
        let (vm, store, dir) = await makeViewModel()
        defer { try? FileManager.default.removeItem(at: dir) }

        guard let target = await store.list().first(where: { $0.page == 0 }) else {
            Issue.record("expected a page-0 starter macro")
            return
        }
        await vm.move(macroID: target.id, toPage: 2, order: 0)

        let moved = await store.macro(id: target.id)
        #expect(moved?.page == 2)
        #expect(moved?.order == 0)
    }

    @Test func testInvokesThroughTheEngineAndReportsAReadableMessage() async throws {
        let (vm, store, dir) = await makeViewModel(allowScriptsGlobal: false)
        defer { try? FileManager.default.removeItem(at: dir) }

        guard let macro = await store.list().first(where: { !$0.isScript }) else {
            Issue.record("expected a non-script starter macro")
            return
        }
        await vm.test(macro)
        #expect(vm.testResultMessage != nil)
    }

    @Test func testOnAScriptMacroIsBlockedWhenGlobalToggleIsOff() async throws {
        let (vm, store, dir) = await makeViewModel(allowScriptsGlobal: false)
        defer { try? FileManager.default.removeItem(at: dir) }

        let scriptMacro = Macro(name: "Deploy", icon: "hammer", action: .shellCommand(command: "echo hi"), page: 0, order: 99)
        try await store.create(scriptMacro)

        await vm.test(scriptMacro)
        #expect(vm.testResultMessage == "Blocked by Mac policy")
    }
}
