// docs/08 §5.2 "Main window = NavigationSplitView with sidebar": Overview / Devices / Macros /
// Diagnostics / Settings. Replaces the per-feature `Window` scenes `AirControlHelperApp.swift` used to
// declare (pairing/trusted-devices/diagnostics/macro-editor/preferences); those windows' content is
// now embedded per-section below via the sibling screens in this directory. Follows system
// appearance (no `.preferredColorScheme` override anywhere in this module) — check light and dark.
import SwiftUI

struct MainWindowView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(MainWindowRouter.self) private var router
    @State private var isServerRunning = false
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<MainWindowRouter.Section?>(
                get: { router.selectedSection },
                set: { if let newValue = $0 { router.select(newValue) } }
            )) {
                ForEach(MainWindowRouter.Section.allCases) { section in
                    Label {
                        HStack(spacing: 6) {
                            Text(section.title)
                            if section == .overview {
                                ConnectionStatusDot(state: statusDotState)
                            }
                        }
                    } icon: {
                        Image(systemName: section.symbolName)
                    }
                    .tag(section)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .navigationTitle("Air Control")
        } detail: {
            NavigationStack {
                detailView
            }
        }
        // docs/08 §5.1: "min 820×560" — `Window`'s `.windowResizability(.contentMinSize)` reads this.
        .frame(minWidth: 820, minHeight: 560)
        .task {
            pollTask?.cancel()
            pollTask = Task {
                while !Task.isCancelled {
                    isServerRunning = await environment.hostService.isRunning
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private var statusDotState: ConnectionStatusDot.State {
        if !environment.connectedSessions.isEmpty { return .connected }
        if isServerRunning { return .idle }
        return .error
    }

    @ViewBuilder
    private var detailView: some View {
        switch router.selectedSection {
        case .overview: OverviewScreen()
        case .devices: DevicesScreen()
        case .macros: MacrosScreen()
        case .diagnostics: DiagnosticsScreen()
        case .settings: SettingsScreen()
        }
    }
}

extension MainWindowRouter.Section {
    var title: String {
        switch self {
        case .overview: "Overview"
        case .devices: "Devices"
        case .macros: "Macros"
        case .diagnostics: "Diagnostics"
        case .settings: "Settings"
        }
    }

    // docs/08 §5.2 sidebar SF Symbols.
    var symbolName: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .devices: "iphone.and.arrow.forward"
        case .macros: "square.grid.2x2"
        case .diagnostics: "waveform.path.ecg"
        case .settings: "gearshape"
        }
    }
}
