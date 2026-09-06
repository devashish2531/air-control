// docs/08 §5.1 "Mac app: from menu-bar agent to proper app": `LSUIElement` is now `NO` (Dock icon
// from the existing AppIcon, project.yml/Info.plist), so this shell is a regular app with a main
// window plus the pre-existing `MenuBarExtra`. Superseded parts of the old spec §5.1.1/§5.1.3 doc
// comment ("no Dock icon; no main window after onboarding", one `Window` scene per feature) are
// replaced by docs/08 §5.2, which this file implements. Main actor hosts SwiftUI (arch §3.3);
// networking/injection/macro executors are owned by other agents and reached only through the
// protocols in ServiceProtocols.swift.
import AppKit
import SwiftUI

@main
struct AirMouseHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment()
    @State private var router = MainWindowRouter()

    var body: some Scene {
        MenuBarExtra {
            MenuBarScene().environment(environment).environment(router)
        } label: {
            MenuBarIconLabel().environment(environment).environment(router)
        }
        .menuBarExtraStyle(.menu)

        // docs/08 §5.1: "Main window `Window("Air Control", id: WindowID.main)`, min 820×560,
        // remembers its frame." `Window(id:)` autosaves/restores its frame under that id by default;
        // the `.frame(minWidth:minHeight:)` inside `MainWindowView` enforces the floor.
        Window("Air Control", id: WindowID.main) {
            MainWindowView().environment(environment).environment(router)
        }
        .defaultSize(width: 900, height: 640)
        .windowResizability(.contentMinSize)
        // docs/08 §5.1: "Closing it does not quit" is `AppDelegate.
        // applicationShouldTerminateAfterLastWindowClosed` below; Cmd-Q still quits via the menu
        // bar's "Quit Air Mouse" button (`MenuBarScene`), which is unaffected by this scene.

        Window("Air Mouse Setup", id: WindowID.onboarding) {
            OnboardingWindow().environment(environment).environment(router)
        }
        .windowResizability(.contentSize)
    }
}

/// docs/08 §5.1: "Closing it does not quit"; "re-activating the app re-opens it" / "launching the
/// app while running re-opens/raises the main window". Both need an `NSApplicationDelegate` — there
/// is no pure-SwiftUI hook for either. Methods are `nonisolated` (the `NSApplicationDelegate`
/// protocol's requirements are not themselves `@MainActor`-isolated) and hop to the main actor
/// explicitly where they touch `MainWindowRouter` (itself `@MainActor`).
final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    nonisolated func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        Task { @MainActor in
            MainWindowRouter.appDelegateBridge?.requestReopen()
        }
        return true
    }
}
