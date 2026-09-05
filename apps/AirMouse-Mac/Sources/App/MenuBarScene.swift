// spec §5.1.2 "Menu (MenuBarExtra, .menu style)" — every row of that table, in order.
import AppKit
import SwiftUI

struct MenuBarScene: View {
    @Environment(AppEnvironment.self) private var environment
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

        Button("Pair New Device…") {
            openWindow(id: WindowID.pairing)
        }

        Toggle("Pause Input", isOn: Binding(
            get: { environment.isInputPaused },
            set: { _ in Task { await environment.toggleInputPaused() } }
        ))

        Divider()

        Button("Macros…") {
            openWindow(id: WindowID.macroEditor)
        }

        Button("Trusted Devices…") {
            openWindow(id: WindowID.trustedDevices)
        }

        Button("Diagnostics…") {
            openWindow(id: WindowID.diagnostics)
        }

        Button("Settings…") {
            openWindow(id: WindowID.preferences)
        }
        .keyboardShortcut(",", modifiers: .command)

        updateMenuItem

        Divider()

        Button("Quit Air Mouse") {
            Task {
                await environment.hostService.stop()
                await MainActor.run { NSApplication.shared.terminate(nil) }
            }
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    /// spec §5.1.2 "hidden when installed via Homebrew ... shows 'Update with brew upgrade --cask
    /// air-mouse' instead" (§9 E-MAC-UPDATE-BREW).
    @ViewBuilder
    private var updateMenuItem: some View {
        if environment.installSource == .homebrewCask {
            Button("Update with: brew upgrade --cask air-mouse") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString("brew upgrade --cask air-mouse", forType: .string)
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
