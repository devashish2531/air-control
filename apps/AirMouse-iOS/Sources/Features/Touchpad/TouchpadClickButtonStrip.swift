// Features/Touchpad/TouchpadClickButtonStrip.swift
// On-screen click button strip (spec §4.1.4, optional): "left 60 % / right 40 % (mirrored for
// left-handed)); press = click{down}, release = click{up}". Drag-to-move on the surface while
// held is handled by the surface itself (`TouchpadUIView`'s gesture engine) — this strip only
// emits the down/up pair on press/release.
//
// Owner UI request: physical-style buttons along the bottom, ~64 pt tall, with haptics (already
// fired by `TouchpadController.clickButtonPressed/Released` via `HapticsService`, unchanged here)
// and a pressed-state visual (fill + inset shadow + slight scale). Press-and-hold on either button
// while a separate finger moves on the pad above is tap-and-drag: this strip and `TouchpadUIView`
// are distinct hit regions (an `HStack` beside the pad in `TouchpadScreen`), each delivering its
// own touches independently — no extra plumbing is needed for the two to compose.

import SwiftUI
import AirMouseFilters

public struct TouchpadClickButtonStrip: View {
    let controller: TouchpadController
    let leftHanded: Bool

    public init(controller: TouchpadController, leftHanded: Bool) {
        self.controller = controller
        self.leftHanded = leftHanded
    }

    public var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                button(.left, width: proxy.size.width * 0.6, label: String(localized: "Left click", comment: "Touchpad click button accessibility label"))
                button(.right, width: proxy.size.width * 0.4, label: String(localized: "Right click", comment: "Touchpad click button accessibility label"))
            }
        }
        .frame(height: 64)
        .environment(\.layoutDirection, leftHanded ? .rightToLeft : .leftToRight)
    }

    @ViewBuilder
    private func button(_ side: ClickButton, width: CGFloat, label: String) -> some View {
        TouchpadClickButton(label: label) { isPressed in
            if isPressed {
                controller.clickButtonPressed(side)
            } else {
                controller.clickButtonReleased(side)
            }
        }
        .frame(width: width)
    }
}

/// One press-and-hold button surface, reporting `isPressed` transitions via `DragGesture(minimumDistance: 0)`
/// (a plain `Button` only fires on a completed tap, not down/up separately).
private struct TouchpadClickButton: View {
    let label: String
    let onPressChange: (Bool) -> Void
    @State private var isPressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isPressed ? Color.secondary.opacity(0.32) : Color.secondary.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(isPressed ? 0.06 : 0.20), lineWidth: 1)
            )
            .shadow(color: .black.opacity(isPressed ? 0 : 0.10), radius: isPressed ? 0 : 3, y: isPressed ? 0 : 1.5)
            .scaleEffect(isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .minimumTapTarget()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        onPressChange(true)
                    }
                    .onEnded { _ in
                        isPressed = false
                        onPressChange(false)
                    }
            )
            .accessibilityLabel(SwiftUI.Text(label))
            .accessibilityAddTraits(.isButton)
    }
}
