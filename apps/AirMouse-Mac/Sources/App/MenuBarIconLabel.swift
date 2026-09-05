// spec §5.1.2 icon states: "cursorarrow.rays monochrome when idle; filled/tinted variant when ≥ 1 device
// connected; exclamationmark.triangle badge when Accessibility is missing or input is paused." This view
// is the MenuBarExtra `label`, which SwiftUI renders eagerly at launch (unlike the lazily-built menu
// `content`), so it also doubles as the "run once at launch" hook for starting services.
import SwiftUI

struct MenuBarIconLabel: View {
    @Environment(AppEnvironment.self) private var environment
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
    }

    private func runLaunchTasks() async {
        environment.startBackgroundRefresh()
        environment.permissions.startPolling(interval: .seconds(10)) // spec §5.2 runtime cadence
        await environment.wireLiveServices()
        await environment.hostService.start()
        // spec §5.2: onboarding is a first-launch flow gated on Accessibility, never shown for the
        // `--loopback` integration harness (which has no interactive session to grant it in).
        if !environment.launchArguments.loopback,
           !environment.permissions.isAccessibilityTrusted,
           !environment.settings.setupCompleted {
            openWindow(id: WindowID.onboarding)
        }
    }
}
