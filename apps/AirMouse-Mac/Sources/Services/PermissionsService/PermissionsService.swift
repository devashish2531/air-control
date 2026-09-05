// spec §5.2 "Permission onboarding (Accessibility only)" and arch §3.3 PermissionsService row.
import ApplicationServices
import AppKit
import Observation

/// Tracks and requests the Accessibility permission the helper needs to post CGEvents (owned by the
/// injection agent) and type on the user's behalf. Never requests Input Monitoring or Screen Recording —
/// this app only needs Accessibility (spec §5.1.1 entitlements, §5.2).
@MainActor
@Observable
public final class PermissionsService {
    public private(set) var isAccessibilityTrusted: Bool
    // Only ever touched on the main actor (init/startPolling/stopPolling/deinit); `nonisolated(unsafe)`
    // lets `deinit` (which runs nonisolated per Swift's default class-deinit rules) cancel it without
    // requiring an `isolated deinit`.
    nonisolated(unsafe) private var pollTask: Task<Void, Never>?

    public init() {
        isAccessibilityTrusted = AXIsProcessTrusted()
    }

    /// Re-checks `AXIsProcessTrusted()` immediately (e.g. on `NSApplication.didBecomeActive`, spec §5.2).
    public func refresh() {
        isAccessibilityTrusted = AXIsProcessTrusted()
    }

    /// Prompts the system Accessibility dialog via `AXIsProcessTrustedWithOptions` (spec §5.2 step 1,
    /// "Request" button). Does not itself start polling.
    @discardableResult
    public func requestAccessibility() -> Bool {
        // `kAXTrustedCheckOptionPrompt` is an `Unmanaged<CFString>!` global from the ApplicationServices C
        // API that Swift 6 flags as non-concurrency-safe shared mutable state. Its value is the stable,
        // documented string "AXTrustedCheckOptionPrompt", so using the literal avoids referencing the
        // global at all.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        isAccessibilityTrusted = trusted
        return trusted
    }

    /// Deep link to Privacy & Security › Accessibility (spec §5.2, §9 E-MAC-AX recovery action).
    public func openSystemSettingsAccessibility() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Polls `AXIsProcessTrusted()` on `interval` while a caller needs it — 2 s while onboarding is visible,
    /// 10 s at runtime (spec §5.2). Calling this again cancels any previous poll.
    public func startPolling(interval: Duration) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else { return }
                self.refresh()
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    deinit {
        pollTask?.cancel()
    }
}
