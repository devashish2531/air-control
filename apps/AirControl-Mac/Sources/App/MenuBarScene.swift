// spec §5.1.2 "Menu (MenuBarExtra, .menu style)" — every row of that table, in order.
import AppKit
import SwiftUI

struct MenuBarScene: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(MainWindowRouter.self) private var router
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusLine)
            .disabled(true)

        ForEach(environment.connectedSessions) { session in
            Menu(session.deviceName) {
                Text(deviceDetail(session))
                Divider()
                Button("Disconnect") {
                    Task { await environment.hostService.disconnect(sessionID: session.id) }
                }
            }
        }

        Divider()

        // docs/08 §5.2: the standalone pairing/macros/trusted-devices/diagnostics/preferences windows
        // are gone — every menu item below deep-links into the single main window's sidebar instead
        // (`MainWindowRouter`, `Open Air Control` below opens it plain).
        Button("Pair New Device…") {
            router.requestPairing()
            openWindow(id: WindowID.main)
        }

        Toggle("Pause Input", isOn: Binding(
            get: { environment.isInputPaused },
            set: { _ in Task { await environment.toggleInputPaused() } }
        ))

        Divider()

        Button("Open Air Control") {
            openWindow(id: WindowID.main)
        }

        Button("Macros…") {
            router.select(.macros)
            openWindow(id: WindowID.main)
        }

        Button("Trusted Devices…") {
            router.select(.devices)
            openWindow(id: WindowID.main)
        }

        Button("Diagnostics…") {
            router.select(.diagnostics)
            openWindow(id: WindowID.main)
        }

        Button("Preferences…") {
            router.select(.settings)
            openWindow(id: WindowID.main)
        }
        .keyboardShortcut(",", modifiers: .command)

        updateMenuItem

        Divider()

        Button("Quit Air Control") {
            Task {
                await environment.hostService.stop()
                await MainActor.run { NSApplication.shared.terminate(nil) }
            }
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    /// spec §5.1.2 "hidden when installed via Homebrew ... shows 'Update with brew upgrade --cask
    /// air-control' instead" (§9 E-MAC-UPDATE-BREW).
    @ViewBuilder
    private var updateMenuItem: some View {
        if environment.installSource == .homebrewCask {
            Button("Update with: brew upgrade --cask air-control") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString("brew upgrade --cask air-control", forType: .string)
            }
        } else {
            Button("Check for Updates…") {
                Task { await checkForUpdates() }
            }
        }
    }

    private func checkForUpdates() async {
        guard let result = try? await environment.updateService.checkForUpdates() else { return }
        Log.ui.info("Update check: newer=\(result.isNewerAvailable, privacy: .public)")
        if result.isNewerAvailable, let url = result.releaseURL {
            NSWorkspace.shared.open(url)
        }
    }

    private var statusLine: String {
        if !environment.permissions.isAccessibilityTrusted {
            return "Accessibility permission needed"
        }
        if environment.isInputPaused {
            return "Input paused"
        }
        switch environment.connectedSessions.count {
        case 0: return "Not connected"
        case 1: return "1 device connected"
        default: return "\(environment.connectedSessions.count) devices connected"
        }
    }

    private func deviceDetail(_ session: ConnectedSessionInfo) -> String {
        let latency = session.latencyMillis.map { "\($0) ms" } ?? "— ms"
        return "\(session.model) · \(latency)"
    }
}
