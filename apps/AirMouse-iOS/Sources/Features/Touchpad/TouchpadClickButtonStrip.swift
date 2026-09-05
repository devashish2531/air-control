// Features/Touchpad/TouchpadClickButtonStrip.swift
// On-screen click button strip (spec §4.1.4, optional): "left 60 % / right 40 % (mirrored for
// left-handed)); press = click{down}, release = click{up}". Drag-to-move on the surface while
// held is handled by the surface itself (`TouchpadUIView`'s gesture engine) — this strip only
// emits the down/up pair on press/release.

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
        .frame(height: 56)
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
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isPressed ? Color.secondary.opacity(0.35) : Color.secondary.opacity(0.15))
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
