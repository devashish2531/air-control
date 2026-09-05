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
        .overlay(alignment: .top) { debugPairingLabel }
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
                // On iOS 26, an un-grouped topBarLeading item is otherwise sized/clipped by the
                // system's shared Liquid Glass toolbar background, which assumes icon-sized
                // content and truncates our wider capsule label. Opt this item out (API is
                // iOS 26+ only; deployment target is 18) so it draws its own Capsule background
                // at its own intrinsic size instead.
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) {
                        ConnectionPillButton(environment: environment, showDevices: $showDevices)
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        ConnectionPillButton(environment: environment, showDevices: $showDevices)
                    }
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
                // `ViewThatFits` lets the toolbar shrink to the compact label ("Offline"/host
                // name) before iOS would otherwise clip the full label; both variants keep
                // lineLimit(1) so neither ever wraps or truncates mid-word.
                ViewThatFits(in: .horizontal) {
                    Text(label)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(compactLabel)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(compactLabel)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                // Bound the proposal so `ViewThatFits` can actually fall back; without a cap the toolbar
                // proposes unlimited width, the full host name always "fits", and a long name pushes the
                // capsule off the leading edge of the screen.
                .frame(maxWidth: 190)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            // Hug the label's intrinsic width instead of letting the system's toolbar button
            // styling (Liquid Glass on iOS 26) collapse this into a fixed circular glyph slot,
            // which is what was clipping the text down to "t conne".
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .layoutPriority(1)
        .minimumTapTarget()
        // `.sharedBackgroundVisibility(.hidden)` opts this item out of the system's shared
        // Liquid Glass toolbar background — which also opts it out of that background's usual
        // leading safe-area inset, so without this the pill's edge is flush with the screen
        // edge (clipping the leading glyph). Restore a comparable inset by hand.
        .padding(.leading, 18)
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

    /// Shorter fallback for narrow toolbars (compact-width iPhones, or when the settings gear
    /// crowds the trailing side) so the pill degrades to "Offline"/"Searching…"/host name
    /// instead of the system truncating the full label.
    private var compactLabel: String {
        switch environment.connection.connectionState {
        case .idle, .failed: return String(localized: "Offline", comment: "Connection pill compact state")
        case .browsing: return String(localized: "Searching…", comment: "Connection pill compact state")
        case .connecting: return String(localized: "Connecting…", comment: "Connection pill compact state")
        case .pairing: return String(localized: "Pairing…", comment: "Connection pill compact state")
        case .connected(let hostName): return hostName
        case .reconnecting(let hostName): return hostName
        case .suspended: return String(localized: "Paused", comment: "Connection pill compact state")
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
            // See the matching comment on the iPad split view's toolbar: without this, iOS 26's
            // shared Liquid Glass toolbar background sizes the leading item as if it were a
            // small icon button and clips the wider "Not connected" capsule down to a few
            // characters. The API is iOS 26+ only; deployment target is 18.
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarLeading) {
                    ConnectionPillButton(environment: environment, showDevices: showDevices)
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) {
                    ConnectionPillButton(environment: environment, showDevices: showDevices)
                }
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

// MARK: - DEBUG diagnostics (read by XCUITests; invisible to users)

extension RootTabView {
    /// DEBUG-only near-invisible label exposing pairing progress so on-device UI tests can report
    /// *why* pairing failed without root access to the phone's logs. Compiled out of Release.
    @ViewBuilder var debugPairingLabel: some View {
        #if DEBUG
        PairingDebugLabel(environment: environment)
        #else
        EmptyView()
        #endif
    }
}

#if DEBUG
private struct PairingDebugLabel: View {
    let environment: AppEnvironment
    var body: some View {
        let manager = environment.connection as? ConnectionManager
        let progress = manager.map { String(describing: $0.pairingProgress) } ?? "no ConnectionManager"
        let state = String(describing: environment.connection.connectionState)
        Text("debug.pairing=\(progress) state=\(state)")
            .font(.system(size: 6))
            .foregroundStyle(.secondary)
            .opacity(0.02)
            .accessibilityIdentifier("debug.pairingProgress")
            .accessibilityLabel("debug.pairing=\(progress) state=\(state)")
            .allowsHitTesting(false)
    }
}
#endif
