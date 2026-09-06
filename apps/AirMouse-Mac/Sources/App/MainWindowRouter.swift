// docs/08 §5.2: "@Observable MainWindowRouter in Sources/App/ for deep links from the menu bar."
// Single source of truth for which sidebar section the main window ("Air Control", `WindowID.main`)
// shows, so the menu bar's "Pair New Device…"/"Macros…"/"Trusted Devices…"/"Diagnostics…"/"Settings…"
// items (previously separate `Window` scenes, spec §5.1.3) can deep-link into one window instead.
import Observation

@MainActor
@Observable
public final class MainWindowRouter {
    // docs/08 §5.2 sidebar order: Overview, Devices, Macros, Diagnostics, Settings.
    public enum Section: String, CaseIterable, Identifiable, Sendable {
        case overview, devices, macros, diagnostics, settings
        public var id: String { rawValue }
    }

    public var selectedSection: Section = .overview

    /// Bumped by `OverviewScreen`'s observer whenever the menu bar's "Pair New Device…" should show
    /// the inline QR (docs/08 §5.2: "primary button Pair New Device shows the QR inline in the
    /// card"), since the main window may already be open on a different section.
    public private(set) var pairingRequestToken: Int = 0

    /// Bumped whenever something outside SwiftUI needs the main window opened without access to the
    /// `openWindow` environment action — specifically `AirMouseHelperApp.AppDelegate.
    /// applicationShouldHandleReopen` (docs/08 §5.1: "re-activating the app re-opens it" / "launching
    /// the app while running re-opens/raises the main window"). `MenuBarIconLabel`'s persistent view
    /// (rendered for the app's lifetime, unlike window content) observes this token and calls
    /// `openWindow(id: WindowID.main)`.
    public private(set) var reopenRequestToken: Int = 0

    public init() {}

    public func select(_ section: Section) {
        selectedSection = section
    }

    public func requestPairing() {
        selectedSection = .overview
        pairingRequestToken += 1
    }

    public func requestReopen() {
        reopenRequestToken += 1
    }

    /// Bridges `NSApplicationDelegate` callbacks (no `openWindow`/`@Environment` access there) to the
    /// single router instance `AirMouseHelperApp` creates. Set once, from `MenuBarIconLabel`'s
    /// launch-once task (mirrors how that view already doubles as the "run once at launch" hook).
    public static var appDelegateBridge: MainWindowRouter?
}
