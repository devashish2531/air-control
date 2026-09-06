// Features/Macros/MacrosScreen.swift
// Macros tab per spec §4.1.8. Replaces the placeholder: a paged grid of macro buttons synced
// from the Mac (name + SF Symbol icon, script badge), pull-to-refresh, per-macro invoke with
// haptic + toast, the script-kind confirmation sheet (spec §5.5.5), disabled state when the host
// has scripts turned off, in-flight spinners, and error toasts using the exact spec §9 copy via
// `AppError`/`ErrorPresentation` (Support/ErrorPresentation.swift).

import SwiftUI
import UIKit
import AirControlProtocol

public struct MacrosScreen: View {
    @Environment(\.appEnvironment) private var contextEnvironment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var model: MacrosModel?

    private let injectedEnvironment: AppEnvironment?
    private let sink: any RemoteCommandSink

    /// Zero-argument entry point kept for `RootTabView.swift`'s current (unmodified) call site
    /// `case .macros: MacrosScreen()`. See `RemoteScreen.init()`'s doc comment for the same
    /// pattern and rationale.
    public init(sink: any RemoteCommandSink = NoOpRemoteCommandSink()) {
        self.injectedEnvironment = nil
        self.sink = sink
    }

    /// Used by `MacrosFeature.make(environment:sink:)`.
    init(environment: AppEnvironment, sink: any RemoteCommandSink) {
        self.injectedEnvironment = environment
        self.sink = sink
    }

    private var environment: AppEnvironment { injectedEnvironment ?? contextEnvironment }

    public var body: some View {
        Group {
            if let model {
                MacrosGridView(model: model, twoColumnForced: horizontalSizeClass != .regular ? nil : true)
            } else {
                Color.clear
            }
        }
        .task {
            guard model == nil else { return }
            let env = environment
            model = env.macros as? MacrosModel ?? {
                let created = MacrosModel(sink: sink, documentStore: env.documentStore, haptics: env.haptics)
                env.macros = created
                return created
            }()
        }
        .navigationTitle(Text("Macros", comment: "Macros tab navigation title"))
    }
}

private struct MacrosGridView: View {
    @Bindable var model: MacrosModel
    /// `true` forces the iPad two-column layout on top of the user's own "Large buttons" choice
    /// (spec §4.1.10 doesn't call this out explicitly for Macros beyond the phone's own toggle,
    /// so this only ever *adds* the constraint, never removes the user's large-buttons choice).
    let twoColumnForced: Bool?

    var body: some View {
        Group {
            if model.macros.isEmpty && !model.isRefreshing {
                emptyState
            } else {
                pagedGrid
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: Binding(get: { model.largeButtons }, set: { model.largeButtons = $0 })) {
                    Label(String(localized: "Large buttons", comment: "Macros large-buttons toggle"), systemImage: "square.grid.2x2")
                }
                .toggleStyle(.button)
            }
        }
        .appErrorPresentation(Binding(get: { model.currentError }, set: { model.currentError = $0 }))
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                MacroToastView(toast: toast)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(2))
                        if model.toast?.id == toast.id { model.toast = nil }
                    }
            }
        }
        .animation(.default, value: model.toast)
        .sheet(item: Binding(get: { model.pendingConfirmation }, set: { if $0 == nil { model.cancelPendingConfirmation() } })) { request in
            MacroConfirmationSheet(request: request, onConfirm: model.confirmPendingInvoke, onCancel: model.cancelPendingConfirmation)
                .presentationDetents([.medium])
        }
        .task { await model.refresh() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "No macros yet", comment: "Macros empty state title"), systemImage: "square.grid.2x2")
        } description: {
            Text("Add macros in the Air Control menu on your Mac.", comment: "Macros empty state description, spec §4.1.8")
        }
        .refreshable { await model.refresh() }
    }

    private var columns: Int {
        if twoColumnForced == true || model.largeButtons { return 2 }
        return 4
    }

    private var pagedGrid: some View {
        TabView {
            ForEach(model.pageIndices, id: \.self) { page in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns), spacing: 16) {
                        ForEach(model.macros(onPage: page)) { macro in
                            MacroButtonView(
                                macro: macro,
                                isInvoking: model.invokingMacroIDs.contains(macro.id),
                                isDisabled: macro.isScript && !model.scriptsAllowedOnHost,
                                large: model.largeButtons
                            ) {
                                model.tap(macro)
                            }
                        }
                    }
                    .padding()
                }
                // Pull-to-refresh per page (a paging `TabView` has no vertical scroll of its own
                // to attach the gesture to, spec §4.1.8's "Cached set renders instantly on
                // reconnect" implies refresh is available wherever the grid is shown).
                .refreshable { await model.refresh() }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: model.pageIndices.count > 1 ? .always : .never))
    }
}

private struct MacroButtonView: View {
    @Environment(\.appEnvironment) private var environment
    let macro: Macro
    let isInvoking: Bool
    let isDisabled: Bool
    let large: Bool
    let action: () -> Void

    var body: some View {
        Button {
            environment.haptics.fire(.tapClick)
            action()
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: knownSymbol ? macro.icon : "command")
                        .font(large ? .largeTitle : .title2)
                        .frame(width: large ? 56 : 40, height: large ? 56 : 40)
                        .foregroundStyle(tintColor)

                    if macro.isScript {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .accessibilityHidden(true)
                    }
                }
                Text(macro.name)
                    .font(large ? .body : .caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if isInvoking {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, minHeight: A11y.minimumTapTarget)
            .padding(.vertical, large ? 20 : 12)
        }
        .buttonStyle(.bordered)
        .minimumTapTarget()
        .disabled(isInvoking || isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .onAppear { environment.haptics.prepare(.tapClick) }
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isDisabled ? Text("Script macros are turned off on this Mac", comment: "Accessibility hint for a disabled script macro button") : Text(""))
    }

    private var accessibilityLabel: String {
        var parts = [macro.name]
        if macro.isScript { parts.append(String(localized: "script", comment: "Accessibility label suffix marking a macro as a script kind")) }
        if isInvoking { parts.append(String(localized: "running", comment: "Accessibility label suffix while a macro is invoking")) }
        return parts.joined(separator: ", ")
    }

    /// `MacroValidator` (AirControlProtocol) only checks non-emptiness — SF Symbol catalog
    /// validation is an app responsibility per its doc comment. `UIImage(systemName:)` returning
    /// non-nil is the standard way to probe the catalog; unknown icons fall back to `command`
    /// (spec §4.1.8: "icon (SF Symbol, fallback `command`)").
    private var knownSymbol: Bool {
        UIImage(systemName: macro.icon) != nil
    }

    private var tintColor: Color {
        guard let tint = macro.tint else { return .primary }
        return switch tint {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .gray: .gray
        }
    }
}

private struct MacroConfirmationSheet: View {
    let request: MacroConfirmationRequest
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Run \(request.macro.name)?", comment: "Macro confirmation sheet title, spec §4.1.8")
                .font(.title2.weight(.semibold))
            Label(request.kindDescription, systemImage: "gearshape")
                .foregroundStyle(.secondary)
            if request.macro.isScript {
                Label {
                    Text(request.warning)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
                .font(.subheadline)
            } else {
                Text(request.warning)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Button(String(localized: "Cancel", comment: "Macro confirmation sheet cancel button"), role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                Button(String(localized: "Run", comment: "Macro confirmation sheet confirm button"), action: onConfirm)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .accessibilityElement(children: .contain)
    }
}

private struct MacroToastView: View {
    let toast: MacroToast

    var body: some View {
        Label(toast.message, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { MacrosScreen() }
        .environment(\.appEnvironment, .preview())
}
