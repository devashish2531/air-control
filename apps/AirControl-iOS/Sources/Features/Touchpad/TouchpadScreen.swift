// Features/Touchpad/TouchpadScreen.swift
// Touchpad tab (spec §4.1.4, §4.2, §4.1.10). Replaces the placeholder. `TouchpadView` fills a
// card-like pad (docs/08 §2.4: `.secondarySystemBackground` fill, dot grid, 20 pt corner radius,
// `.separator` hairline) beside a dedicated right-edge scroll strip (`TouchpadScrollStrip`), with
// a top-edge overlay (mode ribbon: drag-lock indicator / compact quick-settings trigger — see
// `TouchpadModeRibbon`'s header note), physical-style click buttons reserved via
// `safeAreaInset(edge: .bottom)` so the pad never renders under them, and a latency HUD overlay
// gated by Labs. iPad regular-width landscape reserves a side region for the (placeholder)
// Keys/Macros/Presenter panel, collapsing to a 44 pt rail below 700 pt width (spec §4.1.10);
// portrait regular width and compact width both fall back to the plain surface — see this file's
// deviation note on the resizable drawer.
//
// docs/08 §2.1: no floating connection-status indicator over the pad — the toolbar's
// `ConnectionStatusDot` (App/RootTabView.swift, another agent's file, not modified here) is the
// single indicator app-wide — see `TouchpadModeRibbon.swift`'s header note for the full
// rationale; a right-edge scroll strip (~48 pt) and ~64 pt-tall bottom click buttons per the
// owner's requested layout.
//
// Deviation: spec §4.1.10's "Regular width, portrait: Touchpad above a resizable drawer (drag
// handle; heights 30 % / 50 %)" is not implemented — this agent's directories own the surface and
// motion pipeline, and the side-panel content itself (`TouchpadSidePanelSlot`) is an explicit
// placeholder for another agent regardless of presentation (HStack vs. drawer), so the drawer
// chrome was judged lower priority than the touch/motion pipeline within this pass. Landscape
// (`proxy.size.width > proxy.size.height`) is used as a orientation heuristic since SwiftUI has no
// direct "is landscape" environment value on iOS.
//
// Deviation: spec §4.1.4's "Status bar and home indicator hidden **while touching**" is
// simplified to "hidden whenever this screen is visible" — tracking per-touch visibility would
// need extra state plumbing from `TouchpadUIView` for a purely cosmetic refinement.

import SwiftUI
import AirControlFilters

public struct TouchpadScreen: View {
    @Environment(\.appEnvironment) private var contextEnvironment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var controller: TouchpadController?
    @State private var isSidePanelExpanded = true

    private let injectedEnvironment: AppEnvironment?
    private let motion: any MotionEnqueuing
    private let controlSink: any ControlMessageSink

    private static let idleTimerReason = "touchpad"
    private static let sidePanelLandscapeThreshold: CGFloat = 700

    /// Zero-argument entry point kept for `RootTabView.swift`'s current (unmodified) call site
    /// `case .touchpad: TouchpadScreen()`. Falls back to no-op motion/control sinks until the
    /// integration agent switches that call site to
    /// `TouchpadFeature.make(environment:motion:controlSink:)` with the real `MotionPublisher` and
    /// the Connection agent's control sink.
    public init(motion: any MotionEnqueuing = NoOpMotionEnqueuer(), controlSink: any ControlMessageSink = NoOpControlMessageSink()) {
        self.injectedEnvironment = nil
        self.motion = motion
        self.controlSink = controlSink
    }

    /// Used by `TouchpadFeature.make(environment:motion:controlSink:)`.
    init(environment: AppEnvironment, motion: any MotionEnqueuing, controlSink: any ControlMessageSink) {
        self.injectedEnvironment = environment
        self.motion = motion
        self.controlSink = controlSink
    }

    private var environment: AppEnvironment { injectedEnvironment ?? contextEnvironment }

    public var body: some View {
        Group {
            if let controller {
                layout(controller: controller)
            } else {
                Color.clear
            }
        }
        .environment(\.appEnvironment, environment)
        .task {
            guard controller == nil else { return }
            let newController = TouchpadController(
                userSettings: environment.userSettings,
                motion: motion,
                controlSink: controlSink,
                haptics: environment.haptics
            )
            controller = newController
            newController.pushSettingsToHost()
        }
        .task { environment.idleTimer.acquire(Self.idleTimerReason) }
        .onDisappear { environment.idleTimer.release(Self.idleTimerReason) }
        .persistentSystemOverlays(.hidden)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func layout(controller: TouchpadController) -> some View {
        GeometryReader { proxy in
            let isLandscapeRegular = horizontalSizeClass == .regular && proxy.size.width > proxy.size.height
            HStack(spacing: 0) {
                surface(controller: controller)
                    .frame(minWidth: 320, minHeight: 240)
                if isLandscapeRegular {
                    Divider()
                    if proxy.size.width >= Self.sidePanelLandscapeThreshold, isSidePanelExpanded {
                        TouchpadSidePanelSlot()
                            .frame(width: max(240, proxy.size.width * 0.35))
                    } else {
                        TouchpadSidePanelRail(onExpand: { isSidePanelExpanded = true })
                    }
                }
            }
        }
    }

    // docs/08 §2.4: the pad reads as a distinct surface — `Color(.secondarySystemBackground)`
    // fill, 20 pt continuous corner radius, 1 pt `.separator` hairline border — rather than a
    // flat, edge-to-edge fill indistinguishable from the screen's own background. The scroll
    // strip stays a sibling outside that card (it already has its own subtle track styling), and
    // the click-button strip stays outside it too, in the plain screen background below.
    @ViewBuilder
    private func surface(controller: TouchpadController) -> some View {
        HStack(spacing: 8) {
            pad(controller: controller)
            TouchpadScrollStrip(controller: controller)
        }
        .padding(8)
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom) {
            if controller.showClickButtons {
                TouchpadClickButtonStrip(
                    controller: controller,
                    leftHanded: environment.userSettings.snapshot.appearance.handedness == .left,
                    showCaptions: !environment.userSettings.hasUsedClickButtons
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .latencyHUD(diagnostics: environment.diagnostics, isEnabled: environment.labs.latencyHUD)
    }

    @ViewBuilder
    private func pad(controller: TouchpadController) -> some View {
        ZStack {
            Color(.secondarySystemBackground) // docs/08 §2.4 pad fill
            TouchpadGridBackground()

            TouchpadView(
                config: controller.gestureConfig,
                predictionEnabled: environment.labs.prediction,
                intentSink: controller
            )
            .accessibilityElement(children: .contain)

            VStack(spacing: 0) {
                TouchpadModeRibbon(controller: controller)
                    .padding(.top, 8)
                    .padding(.horizontal, 8)
                #if DEBUG
                TouchpadDebugMotionLabel(environment: environment, controller: controller)
                #endif
                Spacer()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)) // docs/08 §2.4
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 1) // docs/08 §2.4 hairline
        )
    }
}

#Preview {
    TouchpadScreen()
        .environment(\.appEnvironment, .preview())
}
