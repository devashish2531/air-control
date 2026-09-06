// spec §5.1.2 icon states: "cursorarrow.rays monochrome when idle; filled/tinted variant when ≥ 1 device
// connected; exclamationmark.triangle badge when Accessibility is missing or input is paused." This view
// is the MenuBarExtra `label`, which SwiftUI renders eagerly at launch (unlike the lazily-built menu
// `content`), so it also doubles as the "run once at launch" hook for starting services.
import AppKit
import SwiftUI

struct MenuBarIconLabel: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(MainWindowRouter.self) private var router
    @Environment(\.openWindow) private var openWindow
    @State private var didRunLaunchTasks = false

    private var isConnected: Bool { !environment.connectedSessions.isEmpty }
    private var hasWarning: Bool {
        !environment.permissions.isAccessibilityTrusted || environment.isInputPaused
    }

    var body: some View {
        Image(systemName: "cursorarrow.rays")
            .symbolVariant(isConnected ? .fill : .none)
            .overlay(alignment: .bottomTrailing) {
                if hasWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.yellow)
                }
            }
            .task {
                guard !didRunLaunchTasks else { return }
                didRunLaunchTasks = true
                await runLaunchTasks()
            }
            // docs/08 §5.1 "Show in Dock" setting: `initial: true` applies the stored preference the
            // moment this (eagerly-rendered) view appears, in addition to any later toggle.
            .onChange(of: environment.settings.showInDock, initial: true) { _, showInDock in
                NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
            }
            // docs/08 §5.1 "re-activating the app re-opens it" / "launching the app while running
            // re-opens/raises the main window": `AppDelegate.applicationShouldHandleReopen` (no
            // `openWindow` access there) bumps this token; this persistent view is where it's acted on.
            .onChange(of: router.reopenRequestToken) { _, _ in
                openWindow(id: WindowID.main)
            }
    }

    private func runLaunchTasks() async {
        // docs/08 §5.2: lets `AppDelegate.applicationShouldHandleReopen` (no environment/`openWindow`
        // access) reach this run's single `MainWindowRouter` instance.
        MainWindowRouter.appDelegateBridge = router
        environment.startBackgroundRefresh()
        environment.permissions.startPolling(interval: .seconds(10)) // spec §5.2 runtime cadence
        await environment.wireLiveServices()
        await environment.hostService.start()
        if environment.launchArguments.printPairURL {
            // Dev convenience (`--print-pair-url`): expose the pairing URL for on-device automation.
            if let url = try? await environment.hostService.openPairingWindow() {
                print("AIRMOUSE_PAIR_URL=\(url)")
                fflush(stdout)
            } else {
                print("AIRMOUSE_PAIR_URL_ERROR=openPairingWindow failed")
                fflush(stdout)
            }
        }
        // spec §5.2: onboarding is a first-launch flow gated on Accessibility, never shown for the
        // `--loopback` integration harness (which has no interactive session to grant it in).
        // `--show-onboarding` (`LaunchArguments.swift`) is a dev convenience that bypasses that gate.
        if environment.launchArguments.showOnboarding
            || (!environment.launchArguments.loopback
                && !environment.permissions.isAccessibilityTrusted
                && !environment.settings.setupCompleted) {
            openWindow(id: WindowID.onboarding)
        }
    }
}
