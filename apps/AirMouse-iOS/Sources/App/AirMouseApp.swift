// App/AirMouseApp.swift
// Entry point. Builds `AppEnvironment` once, injects it through the SwiftUI environment (arch
// §3.2 "Dependency injection"), and chooses onboarding vs. the root tab UI based on
// `am.onboardingCompleted` (spec §4.1.1). Presents onboarding as a full-screen cover per
// spec §4.1 ("Onboarding and Scan QR are presented as full-screen covers").
//
// Background/foreground forwarding to `ConnectionManager` (arch §3.2: "Background/foreground
// transitions (scenePhase) are forwarded by AirMouseApp") is wired here as a thin `scenePhase`
// observer; the actual state-machine behavior for §4.5.5 belongs to the Connection agent's
// `ConnectionManaging` conformer.

import SwiftUI

@main
struct AirMouseApp: App {
    @State private var environment = AppEnvironment.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appEnvironment, environment)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                environment.idleTimer.isEnabledBySettings = environment.userSettings.snapshot.feedback.keepScreenAwake
            case .inactive, .background:
                break
            @unknown default:
                break
            }
        }
    }
}

/// Chooses onboarding vs. the root UI. Kept as its own view (rather than inlined in the Scene)
/// so it can read `@Environment(\.appEnvironment)` — unavailable at `App.body` construction time.
private struct RootView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var isOnboardingPresented = false

    var body: some View {
        RootTabView()
            .task {
                #if DEBUG
                // Test hook: `AIRMOUSE_PAIR_URL` env (or `-pairURL <url>` argument) routes a pairing URL at
                // launch so XCUITests can pair against a real Mac without the camera. Debug builds only.
                if let urlString = Self.launchPairingURLString(), let url = URL(string: urlString) {
                    environment.userSettings.onboardingCompleted = true
                    isOnboardingPresented = false
                    environment.pairingRouter.routePairing(url: url)
                    return
                }
                #endif
                isOnboardingPresented = !environment.userSettings.onboardingCompleted
            }
            .fullScreenCover(isPresented: $isOnboardingPresented) {
                OnboardingScreen(onFinished: { isOnboardingPresented = false })
            }
    }
}

#if DEBUG
extension RootView {
    /// `AIRMOUSE_PAIR_URL=airmouse://…` in the environment, or `-pairURL airmouse://…` in the arguments.
    static func launchPairingURLString() -> String? {
        let info = ProcessInfo.processInfo
        if let env = info.environment["AIRMOUSE_PAIR_URL"], !env.isEmpty { return env }
        let args = info.arguments
        if let index = args.firstIndex(of: "-pairURL"), index + 1 < args.count { return args[index + 1] }
        return nil
    }
}
#endif
