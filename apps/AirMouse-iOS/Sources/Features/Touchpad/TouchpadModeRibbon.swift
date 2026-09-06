// Features/Touchpad/TouchpadModeRibbon.swift
// docs/08 §2.1: loses its connection text entirely — the toolbar's `ConnectionStatusDot`
// (App/RootTabView.swift, another agent's file, not modified here) is the touchpad's single
// connection indicator, so this view must never float a second host-name/dot pill over the pad.
// What remains is a compact 44 pt trailing control (`slider.horizontal.3`) that opens the
// touchpad quick settings (`TouchpadQuickSettingsView`), plus the "Dragging" indicator, which is
// drag-lock state, not connection status, and stays on the pad. The pointer-sensitivity slider
// that used to live inline here (long-press reveal) has moved into that quick-settings sheet.
//
// The row is trailing-anchored (`Spacer()` before the quick-settings button,
// `.frame(maxWidth: .infinity, alignment: .trailing)`), never centered over the pad — owner
// item 5: "move any overlays off the pad centre to the top edge of the pad".

import SwiftUI

public struct TouchpadModeRibbon: View {
    @Environment(\.appEnvironment) private var environment
    let controller: TouchpadController

    @State private var showQuickSettings = false

    public init(controller: TouchpadController) {
        self.controller = controller
    }

    public var body: some View {
        HStack(spacing: 8) {
            if controller.isDragLockEngaged {
                Label {
                    Text("Dragging", comment: "Touchpad mode ribbon drag-lock indicator")
                } icon: {
                    Image(systemName: "hand.draw")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .accessibilityAddTraits(.isSelected)
            }
            Spacer(minLength: 8)
            quickSettingsButton
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .sheet(isPresented: $showQuickSettings) {
            TouchpadQuickSettingsView(controller: controller, isElevatedLatency: isElevatedLatency)
                .environment(\.appEnvironment, environment)
        }
    }

    private var quickSettingsButton: some View {
        Button {
            showQuickSettings = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .minimumTapTarget()
        .accessibilityLabel(Text("Touchpad settings", comment: "Accessibility label for the touchpad quick settings button"))
        .accessibilityHint(Text("Opens pointer sensitivity settings", comment: "Accessibility hint for the touchpad quick settings button"))
    }

    private var isElevatedLatency: Bool {
        environment.diagnostics.latest?.channel == .tcpFallback
    }
}

#Preview {
    let env = AppEnvironment.preview()
    TouchpadModeRibbon(controller: TouchpadController(
        userSettings: env.userSettings,
        motion: NoOpMotionEnqueuer(),
        controlSink: NoOpControlMessageSink(),
        haptics: env.haptics
    ))
    .environment(\.appEnvironment, env)
}
