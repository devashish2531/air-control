// App/RootTabView.swift
// Root navigation per spec §4.1: TabView with five tabs (Touchpad, Air Pointer, Keyboard, Remote,
// Macros) plus a toolbar connection status dot (tap → Devices, docs/08 §2.1) and a Settings gear.
// The Air Pointer tab is hidden when the device has no gyroscope (FR-GY-012). Default tab is
// configurable (AM-ST-05). iPad regular width uses `NavigationSplitView` (spec §4.1.10 drives this
// at the screen level too, but the *root* choice between tab bar and split view is this file's
// call, per this agent's assignment) — size class, not `userInterfaceIdiom`, decides.
//
// docs/08 §2.2: injects the live `TabSwitcher` so features that cover the root tab bar (the
// Keyboard tab's input accessory bar) can switch tabs / open Settings without owning this file's
// state.
// docs/08 §2.3: applies `.preferredColorScheme` from `UserSettings.snapshot.appearance.mode` at
// the root so every sheet/cover presented from here (onboarding, Devices, Settings) inherits it.
// The theme agent is writing `Sources/Support/Appearance.swift`'s `AppearanceSetting.colorScheme`
// extension separately; the mapping below is written inline instead of depending on that type so
// this file still builds if that extension lands after this one.

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
        // docs/08 §2.3
        .preferredColorScheme(colorScheme(for: environment.userSettings.snapshot.appearance.mode))
        // docs/08 §2.2
        .environment(\.tabSwitcher, TabSwitcher(
            switchTo: { selectedTab = $0 },
            openSettings: { showSettings = true }
        ))
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
                        .airPointerRootToolbar(showDevices: $showDevices, showSettings: $showSettings, environment: environment)
                }
                .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                .tag(tab)
                .accessibilityIdentifier("tab.\(tab.rawValue)")
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
            .navigationTitle(Text("Air Pointer", comment: "iPad sidebar navigation title"))
        } detail: {
            // docs/08 §2.1: the status dot is the top-leading item on every tab's own toolbar
            // (matching the iPhone tab view), not the sidebar column, so it reads per-screen.
            NavigationStack {
                destination(for: selectedTab)
                    .airPointerRootToolbar(showDevices: $showDevices, showSettings: $showSettings, environment: environment)
            }
        }
    }

    private var visibleTabs: [AppTab] {
        AppTab.allCases.filter { $0 != .airPointer || environment.gyro.isGyroAvailable }
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        switch tab {
        case .touchpad:
            TouchpadFeature.make(environment: environment, motion: environment.motionPublisher, controlSink: environment.controlSink)
        case .airPointer:
            AirPointerScreen(viewModel: makeAirPointerViewModel())
        case .keyboard:
            KeyboardFeature.make(environment: environment)
        case .remote:
            RemoteFeature.make(environment: environment, sink: environment.remoteSink)
        case .macros:
            MacrosFeature.make(environment: environment, sink: environment.remoteSink)
        }
    }

    /// `AirPointerFeature.make(environment:)` alone would default both `controlSink` (clicks/
    /// scroll-phase) *and*, more importantly, the view model's motion-delta `motionSink` to
    /// no-ops — its own `makeViewModel(environment:controlSink:)` overload only lets a caller fix
    /// the former (see that factory's doc comment: it derives `motionSink` from `environment
    /// .motion as? MotionEnqueuing`, which `MotionPublisherStatusAdapter` never satisfies). This
    /// mirrors that factory's engine-reuse logic but passes `environment.motionPublisher`
    /// (`ControlMessageSink`+`MotionEnqueuing`, both real once `AppEnvironment.live()` wires them)
    /// directly into `AirPointerViewModel`'s own public initializer, so Air Pointer clicks and its
    /// touch-scroll strip (spec §3.6) both reach the live connection.
    @MainActor
    private func makeAirPointerViewModel() -> AirPointerViewModel {
        let localSettings = AirPointerLocalSettings()
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
        return AirPointerViewModel(
            engine: engine,
            localSettings: localSettings,
            userSettings: environment.userSettings,
            haptics: environment.haptics,
            controlSink: environment.controlSink,
            motionSink: environment.motionPublisher
        )
    }

    /// docs/08 §2.3 — written inline (rather than depending on the theme agent's
    /// `AppearanceSetting.colorScheme` extension in `Sources/Support/Appearance.swift`) so this
    /// file builds regardless of that file's landing order.
    private func colorScheme(for mode: AppearanceMode) -> ColorScheme? {
        switch mode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Shared toolbar (connection status dot + gear)

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
    func airPointerRootToolbar(showDevices: Binding<Bool>, showSettings: Binding<Bool>, environment: AppEnvironment) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ConnectionStatusDot(environment: environment, showDevices: showDevices)
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
        // How this launch's own client identity was resolved (reused / stale-replaced / minted /
        // ephemeral) plus each candidate address's outcome: without these, a handshake that stalls
        // rather than fails is indistinguishable on-device from "the Mac wasn't reachable".
        let identity = ConnectionFeature.identityTrace
        let attempts = manager.map { manager in
            manager.lastConnectionAttempts.map { "\($0.address):\($0.outcome)" }.joined(separator: ";")
        } ?? ""
        let summary = "debug.pairing=\(progress) state=\(state) identity=\(identity) attempts=[\(attempts)]"
        Text(summary)
            .font(.system(size: 6))
            .foregroundStyle(.secondary)
            .opacity(0.02)
            .accessibilityIdentifier("debug.pairingProgress")
            .accessibilityLabel(summary)
            .allowsHitTesting(false)
    }
}
#endif
