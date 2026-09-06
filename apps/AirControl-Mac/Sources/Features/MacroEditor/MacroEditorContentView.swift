// spec §5.5.3 Macro editor: "a left page list (Pages 1–6, reorder by drag) and a right grid mirroring
// the phone layout (drag to reorder across pages)." docs/08 §5.2: embedded as the main window's
// "Macros" sidebar section (`Features/MainWindow/MacrosScreen.swift`) instead of its own `Window`
// scene — renamed from `MacroEditorWindow` accordingly.
//
// This view builds its own `MacroStore`/`MacroEngine` via `MacroFeature.make(environment:)` rather
// than reading `environment.macroStore` (the shell's tiny `MacroStoring` DI slot only exposes
// `macroCount` for the menu bar, per `App/ServiceProtocols.swift` — not owned by this module). See
// `MacroEngine+Environment.swift`'s doc comment: the integration agent is expected to eventually share
// one `MacroStore` instance between the menu bar and this window; until then both read/write the same
// `Macros.json` file through independent `DocumentStore`-backed actors, which is safe (atomic writes,
// revision-tracked) but not instantaneously consistent between the two.
import AirControlProtocol
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MacroEditorContentView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: MacroEditorViewModel?

    var body: some View {
        Group {
            if let viewModel {
                MacroEditorContent(viewModel: viewModel)
            } else {
                ProgressView("Loading macros…")
                    .frame(minWidth: 480, minHeight: 360)
            }
        }
        .task {
            if viewModel == nil {
                // Prefer the shared instance `AppEnvironment.wireLiveServices()` already built (so the
                // menu bar's macro count and this editor read/write the same `MacroStore`); only build a
                // standalone one when the environment is still placeholder/preview-backed.
                let feature: MacroFeature
                if let shared = environment.macroFeature {
                    feature = shared
                } else {
                    feature = await MacroFeature.make(environment: environment)
                }
                viewModel = MacroEditorViewModel(
                    store: feature.store,
                    engine: feature.engine,
                    allowScriptsGlobal: environment.settings.allowScriptsGlobal
                )
                await viewModel?.refresh()
            }
        }
    }
}

/// A trivial `FileDocument` wrapper so `.fileExporter` can write the bytes `MacroStoreProviding.
/// exportDocument()` already produced (spec §5.5.2 Export: "writes the same document via `NSSavePanel`").
struct MacroJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct MacroEditorContent: View {
    @Bindable var viewModel: MacroEditorViewModel
    @Environment(MainWindowRouter.self) private var router
    @Environment(\.openWindow) private var openWindow
    @State private var isImporterPresented = false
    @State private var isExporterPresented = false
    @State private var exportDocument: MacroJSONDocument = MacroJSONDocument(data: Data())

    var body: some View {
        NavigationSplitView {
            List(0..<ProtocolConstants.macroMaxPages, id: \.self, selection: Binding<Int?>(
                get: { viewModel.selectedPage },
                set: { if let value = $0 { viewModel.selectedPage = value } }
            )) { page in
                Text("Page \(page + 1)")
                    .badge(viewModel.macros(onPage: page).count)
                    .tag(page)
                    .dropDestination(for: String.self) { items, _ in
                        guard let idString = items.first, let id = UUID(uuidString: idString) else { return false }
                        Task {
                            await viewModel.move(macroID: id, toPage: page, order: viewModel.macros(onPage: page).count)
                        }
                        return true
                    }
            }
            .navigationSplitViewColumnWidth(min: 120, ideal: 140)
        } detail: {
            MacroGridView(viewModel: viewModel)
                .toolbar {
                    ToolbarItemGroup {
                        Button {
                            viewModel.startCreating()
                        } label: {
                            Label("Add Macro", systemImage: "plus")
                        }
                        Button {
                            isImporterPresented = true
                        } label: {
                            Label("Import…", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            Task {
                                if let data = await viewModel.exportData() {
                                    exportDocument = MacroJSONDocument(data: data)
                                    isExporterPresented = true
                                }
                            }
                        } label: {
                            Label("Export…", systemImage: "square.and.arrow.up")
                        }
                    }
                }
        }
        .sheet(item: $viewModel.editingDraft) { _ in
            if let binding = Binding($viewModel.editingDraft) {
                MacroInspectorView(
                    draft: binding,
                    allowScriptsGlobal: viewModel.allowScriptsGlobal,
                    isNew: viewModel.isCreatingNew,
                    onSave: { Task { await viewModel.saveDraft() } },
                    onCancel: { viewModel.cancelEditing() },
                    onTest: {
                        Task {
                            if let macro = binding.wrappedValue.makeMacro() {
                                await viewModel.test(macro)
                            }
                        }
                    },
                    // docs/08 §5.2: Preferences is now the main window's "Settings" sidebar section,
                    // not its own `Window` scene.
                    onOpenSecurityPreferences: {
                        router.select(.settings)
                        openWindow(id: WindowID.main)
                    }
                )
            }
        }
        .confirmationDialog(
            "Delete \(viewModel.pendingDeleteName ?? "this macro")?",
            isPresented: Binding(
                get: { viewModel.pendingDeleteID != nil },
                set: { if !$0 { viewModel.cancelDelete() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await viewModel.confirmDelete() } }
            Button("Cancel", role: .cancel) { viewModel.cancelDelete() }
        }
        .alert("Couldn't save macro", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Test result", isPresented: Binding(
            get: { viewModel.testResultMessage != nil },
            set: { if !$0 { viewModel.testResultMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.testResultMessage = nil }
        } message: {
            Text(viewModel.testResultMessage ?? "")
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                Task {
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url) {
                        await viewModel.previewImport(data: data)
                    }
                }
            case .failure(let error):
                viewModel.importError = String(describing: error)
            }
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Macros"
        ) { _ in }
        .confirmationDialog(
            "Import \(viewModel.pendingImportPreview?.importedCount ?? 0) macros?",
            isPresented: Binding(
                get: { viewModel.pendingImportPreview != nil },
                set: { if !$0 { viewModel.cancelImport() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Import") { Task { await viewModel.confirmImport() } }
            Button("Cancel", role: .cancel) { viewModel.cancelImport() }
        } message: {
            if let preview = viewModel.pendingImportPreview {
                Text(
                    "\(preview.importedCount) macros (\(preview.replacedCount) replacing existing), including \(preview.scriptCount) script macro(s) imported disabled (spec §5.5.2)."
                )
            }
        }
        .alert("Couldn't import macros", isPresented: Binding(
            get: { viewModel.importError != nil },
            set: { if !$0 { viewModel.importError = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.importError = nil }
        } message: {
            Text(viewModel.importError ?? "")
        }
    }
}

private struct MacroGridView: View {
    @Bindable var viewModel: MacroEditorViewModel

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(viewModel.macros(onPage: viewModel.selectedPage).enumerated()), id: \.element.id) { index, macro in
                    MacroTileView(macro: macro)
                        .contextMenu {
                            Button("Edit") { viewModel.startEditing(macro) }
                            Button("Duplicate") { Task { await viewModel.duplicate(macro.id) } }
                            Button("Test") { Task { await viewModel.test(macro) } }
                            Divider()
                            Button("Delete", role: .destructive) { viewModel.requestDelete(macro.id) }
                        }
                        .onTapGesture(count: 2) { viewModel.startEditing(macro) }
                        .draggable(macro.id.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            guard let idString = items.first, let id = UUID(uuidString: idString) else { return false }
                            Task { await viewModel.move(macroID: id, toPage: viewModel.selectedPage, order: index) }
                            return true
                        }
                }
            }
            .padding()
        }
        .background(.background)
        .overlay {
            if viewModel.macros(onPage: viewModel.selectedPage).isEmpty {
                ContentUnavailableView(
                    "No macros on this page",
                    systemImage: "square.grid.3x3",
                    description: Text("Click + to add one, or drag a macro here from another page.")
                )
            }
        }
    }
}

private struct MacroTileView: View {
    let macro: Macro

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: NSImage(systemSymbolName: macro.icon, accessibilityDescription: nil) != nil ? macro.icon : "command")
                .font(.system(size: 28))
                .foregroundStyle(macro.tint?.swiftUIColor ?? .primary)
                .frame(width: 56, height: 56)
                .background((macro.tint?.swiftUIColor ?? .gray).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(macro.name)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 96)
            if macro.isScript {
                Label("Script", systemImage: "exclamationmark.shield.fill")
                    .labelStyle(.iconOnly)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(8)
    }
}
