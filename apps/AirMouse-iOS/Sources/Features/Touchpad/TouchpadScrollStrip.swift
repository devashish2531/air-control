// Features/Touchpad/TouchpadScrollStrip.swift
// Owner UI request: a dedicated vertical scroll strip along the right edge of the touchpad
// surface (~44–56 pt wide, full height of the pad area, subtle track with a grabber indicator). A
// one-finger vertical drag here produces scroll intents (began/changed/ended with velocity →
// momentum), never pointer motion — kept as a physically separate hit region from `TouchpadView`
// (an `HStack` sibling in `TouchpadScreen`, not an overlay on top of it) so it never contends with
// the pad's own single-finger move / two-finger scroll gestures (spec §4.2.3's finger-count state
// machine is unmodified by this file).
//
// Routes through `TouchpadController.scrollStripChanged/scrollStripEnded`, which reuse the pad's
// existing `.scrollPhaseBegan`/`.scrollChanged`/`.scrollPhaseEnded` intent path (→
// `MotionEnqueuing.enqueueScroll` + `ControlMessageSink.sendScrollPhase`, spec §4.2.5) — no new
// wire path is invented here. Mirrors `AirMouseScrollStrip` (Features/AirMouse, another agent's
// file, not modified here)'s single-finger-strip pattern, including reading
// `DragGesture.Value.velocity` directly for the lift velocity.

import SwiftUI

public struct TouchpadScrollStrip: View {
    let controller: TouchpadController

    @State private var isDragging = false

    public static let width: CGFloat = 48

    public init(controller: TouchpadController) {
        self.controller = controller
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDragging ? Color.accentColor.opacity(0.20) : Color.secondary.opacity(0.08))
            // Grabber indicator (owner spec: "subtle track with a grabber/indicator").
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Color.secondary.opacity(isDragging ? 0.55 : 0.35))
                .frame(width: 4, height: 40)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    isDragging = true
                    controller.scrollStripChanged(translationY: value.translation.height)
                }
                .onEnded { value in
                    isDragging = false
                    controller.scrollStripEnded(velocityY: value.velocity.height)
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SwiftUI.Text("Scroll strip", comment: "Touchpad right-edge scroll strip accessibility label"))
        .accessibilityHint(SwiftUI.Text("Slide up or down to scroll", comment: "Touchpad right-edge scroll strip accessibility hint"))
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
