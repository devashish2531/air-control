// App/RootTabView.swift
// Root navigation per spec §4.1: TabView with five tabs (Touchpad, Air Mouse, Keyboard, Remote,
// Macros) plus a toolbar connection pill (tap → Devices) and a Settings gear. The Air Mouse tab
// is hidden when the device has no gyroscope (FR-GY-012). Default tab is configurable
// (AM-ST-05). iPad regular width uses `NavigationSplitView` (spec §4.1.10 drives this at the
// screen level too, but the *root* choice between tab bar and split view is this file's call,
// per this agent's assignment) — size class, not `userInterfaceIdiom`, decides.

import Combine
import SwiftUI

public struct RootTabView: View {
    @Environment(\.appEnvironment) private var environment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedTab: AppTab = .touchpad
    @State private var hasAppliedDefaultTab = false
    @State private var showDevices = false
    @State private var showSettings = false

    public init() {}

    public var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadSplitView
            } else {
                phoneTabView
            }
        }
        .task {
            guard !hasAppliedDefaultTab else { return }
            hasAppliedDefaultTab = true
            selectedTab = environment.userSettings.defaultTab
        }
        .sheet(isPresented: $showDevices) {
            NavigationStack { DevicesScreen() }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsScreen() }
        }
        .onOpenURL { url in
            guard DeepLink.isPairingURL(url) else {
                Log.deepLink.notice("Ignoring URL with unrecognised scheme/host")
                return
            }
            Log.deepLink.info("Routing pairing deep link")
            environment.pairingRouter.routePairing(url: url)
        }
        // spec §4.1's pointer-spotlight-style handoff: the Remote feature posts this when it
        // wants the shell to jump back to the Touchpad tab (RemoteModel.swift).
        .onReceive(NotificationCenter.default.publisher(for: RemoteModel.switchToTouchpadNotification)) { _ in
            selectedTab = .touchpad
        }
    }

    // MARK: iPhone / compact width

    private var phoneTabView: some View {
        TabView(selection: $selectedTab) {
            ForEach(visibleTabs) { tab in
                NavigationStack {
                    destination(for: tab)
                        .airMouseRootToolbar(showDevices: $showDevices, showSettings: $showSettings, environment: environment)
                }
                .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                .tag(tab)
            }
        }
    }

    // MARK: iPad / regular width

    private var iPadSplitView: some View {
        NavigationSplitView {
            // iOS's `List` only supports optional-selection bindings (the non-optional
            // `selection:` initializers are macOS-only), so bridge through an optional binding.
            List(selection: Binding(
                get: { Optional(selectedTab) },
                set: { newValue in if let newValue { selectedTab = newValue } }
            )) {
                ForEach(visibleTabs) { tab in
                    Label(tab.title, systemImage: tab.systemImage).tag(tab)
                }
            }
            .navigationTitle(Text("Air Mouse", comment: "iPad sidebar navigation title"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ConnectionPillButton(environment: environment, showDevices: $showDevices)
                }
            }
        } detail: {
            NavigationStack {
                destination(for: selectedTab)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            SettingsGearButton(showSettings: $showSettings)
                        }
                    }
            }
        }
    }

    private var visibleTabs: [AppTab] {
        AppTab.allCases.filter { $0 != .airMouse || environment.gyro.isGyroAvailable }
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        switch tab {
        case .touchpad:
            TouchpadFeature.make(environment: environment, motion: environment.motionPublisher, controlSink: environment.controlSink)
        case .airMouse:
            AirMouseScreen(viewModel: makeAirMouseViewModel())
        case .keyboard:
            KeyboardFeature.make(environment: environment)
        case .remote:
            RemoteFeature.make(environment: environment, sink: environment.remoteSink)
        case .macros:
            MacrosFeature.make(environment: environment, sink: environment.remoteSink)
        }
    }

    /// `AirMouseFeature.make(environment:)` alone would default both `controlSink` (clicks/
    /// scroll-phase) *and*, more importantly, the view model's motion-delta `motionSink` to
    /// no-ops — its own `makeViewModel(environment:controlSink:)` overload only lets a caller fix
    /// the former (see that factory's doc comment: it derives `motionSink` from `environment
    /// .motion as? MotionEnqueuing`, which `MotionPublisherStatusAdapter` never satisfies). This
    /// mirrors that factory's engine-reuse logic but passes `environment.motionPublisher`
    /// (`ControlMessageSink`+`MotionEnqueuing`, both real once `AppEnvironment.live()` wires them)
    /// directly into `AirMouseViewModel`'s own public initializer, so Air Mouse clicks and its
    /// touch-scroll strip (spec §3.6) both reach the live connection.
    @MainActor
    private func makeAirMouseViewModel() -> AirMouseViewModel {
        let localSettings = AirMouseLocalSettings()
        let engine: GyroEngine
        if let existing = environment.gyro as? GyroEngine {
            engine = existing
        } else {
            let gyro = environment.userSettings.snapshot.gyro
            engine = GyroEngine(
                sink: environment.motionPublisher,
                settings: GyroEngineSettings(
                    sensitivity: Double(gyro.sensitivity),
                    smoothingSlider: Double(gyro.smoothing),
                    deadZoneDegPerSec: gyro.deadZoneDegreesPerSecond,
                    clutchMode: localSettings.clutchMode,
                    recenterMode: localSettings.recenterMode,
                    isOrientationLocked: localSettings.isOrientationLocked
                )
            )
            environment.gyro = engine
        }
        return AirMouseViewModel(
            engine: engine,
            localSettings: localSettings,
            userSettings: environment.userSettings,
            haptics: environment.haptics,
            controlSink: environment.controlSink,
            motionSink: environment.motionPublisher
        )
    }
}

// MARK: - Shared toolbar (connection pill + gear)

private struct ConnectionPillButton: View {
    let environment: AppEnvironment
    @Binding var showDevices: Bool

    var body: some View {
        Button {
            showDevices = true
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
        }
        .minimumTapTarget()
        .accessibilityLabel(Text("Connection: \(label)", comment: "Accessibility label for the connection pill"))
        .accessibilityHint(Text("Opens Devices", comment: "Accessibility hint for the connection pill"))
    }

    private var label: String {
        switch environment.connection.connectionState {
        case .idle: return String(localized: "Not connected", comment: "Connection pill state")
        case .browsing: return String(localized: "Searching…", comment: "Connection pill state")
        case .connecting: return String(localized: "Connecting…", comment: "Connection pill state")
        case .pairing: return String(localized: "Pairing…", comment: "Connection pill state")
        case .connected(let hostName): return hostName
        case .reconnecting(let hostName): return String(localized: "Reconnecting to \(hostName)…", comment: "Connection pill state")
        case .suspended: return String(localized: "Suspended", comment: "Connection pill state")
        case .failed: return String(localized: "Not connected", comment: "Connection pill state")
        }
    }

    private var dotColor: Color {
        switch environment.connection.connectionState {
        case .connected: return .green
        case .connecting, .pairing, .reconnecting, .browsing: return .yellow
        case .idle, .suspended, .failed: return .secondary
        }
    }
}

private struct SettingsGearButton: View {
    @Binding var showSettings: Bool

    var body: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
        .minimumTapTarget()
        .accessibilityLabel(Text("Settings", comment: "Accessibility label for the settings gear button"))
    }
}

private extension View {
    func airMouseRootToolbar(showDevices: Binding<Bool>, showSettings: Binding<Bool>, environment: AppEnvironment) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ConnectionPillButton(environment: environment, showDevices: showDevices)
            }
            ToolbarItem(placement: .topBarTrailing) {
                SettingsGearButton(showSettings: showSettings)
            }
        }
    }
}

#Preview {
    RootTabView()
        .environment(\.appEnvironment, .preview())
}
