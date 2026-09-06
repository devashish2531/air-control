// spec §5.3.8, §5.7.3; arch §3.3 HostStateObserver row.
import AppKit
import Foundation
import Observation

/// Observes frontmost-app changes, display topology, the system natural-scroll preference, and pause
/// state, and publishes a combined `HostStateSnapshot`. `SessionManager` (owned by the networking agent)
/// is expected to read `snapshot` and serialize it into the wire `hostState` message.
@MainActor
@Observable
public final class HostStateObserver {
    public private(set) var snapshot: HostStateSnapshot

    private let displayTopology: DisplayTopology
    private let permissions: PermissionsService
    private var isPausedProvider: @MainActor () -> Bool
    // `nonisolated(unsafe)`: only touched from init/deinit; needed so `deinit` (nonisolated per Swift's
    // default class-deinit rules) can remove the observers. `@ObservationIgnored` keeps the
    // `@Observable` macro from re-wrapping storage access in a way that would otherwise make
    // `nonisolated(unsafe)` a no-op on these properties.
    @ObservationIgnored
    nonisolated(unsafe) private var activationObserver: NSObjectProtocol?
    @ObservationIgnored
    nonisolated(unsafe) private var scrollDirectionObserver: NSObjectProtocol?

    public init(
        displayTopology: DisplayTopology,
        permissions: PermissionsService,
        isPausedProvider: @escaping @MainActor () -> Bool
    ) {
        self.displayTopology = displayTopology
        self.permissions = permissions
        self.isPausedProvider = isPausedProvider
        snapshot = HostStateSnapshot(
            naturalScrollEnabled: Self.readSystemNaturalScroll(),
            displayTopology: displayTopology.snapshot,
            isPaused: isPausedProvider(),
            isAccessibilityTrusted: permissions.isAccessibilityTrusted,
            frontmostAppBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            timestamp: Date()
        )

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let bundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            // `queue: .main` guarantees this runs on the main thread/actor already.
            MainActor.assumeIsolated {
                self?.refresh(frontmostAppBundleID: bundleID)
            }
        }

        // Undocumented but widely relied-upon distributed notification for scroll-direction changes
        // (spec/research note: no public change notification exists; treated as optional/best-effort).
        scrollDirectionObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("SwipeScrollDirectionDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // `queue: .main` guarantees this runs on the main thread/actor already.
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    /// Swaps in a new pause-state provider. Callers that cannot supply the final closure at `init` time
    /// (e.g. because it needs to capture a container whose own `init` isn't finished yet) can pass a
    /// placeholder up front and call this once the real value is available.
    public func updatePausedProvider(_ provider: @escaping @MainActor () -> Bool) {
        isPausedProvider = provider
    }

    /// Re-reads every input and republishes `snapshot`, keeping the current frontmost app bundle id.
    public func refresh() {
        refresh(frontmostAppBundleID: snapshot.frontmostAppBundleID)
    }

    /// Re-reads every input and republishes `snapshot` with a newly-observed frontmost app bundle id
    /// (spec §5.3.8 FR-PR-005).
    public func refresh(frontmostAppBundleID: String?) {
        snapshot = HostStateSnapshot(
            naturalScrollEnabled: Self.readSystemNaturalScroll(),
            displayTopology: displayTopology.snapshot,
            isPaused: isPausedProvider(),
            isAccessibilityTrusted: permissions.isAccessibilityTrusted,
            frontmostAppBundleID: frontmostAppBundleID,
            timestamp: Date()
        )
    }

    /// `com.apple.swipescrolldirection` in the global domain (spec §5.7.3 / arch §3.3).
    private static func readSystemNaturalScroll() -> Bool {
        UserDefaults(suiteName: UserDefaults.globalDomain)?.bool(forKey: "com.apple.swipescrolldirection") ?? true
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let scrollDirectionObserver {
            DistributedNotificationCenter.default().removeObserver(scrollDirectionObserver)
        }
    }
}
