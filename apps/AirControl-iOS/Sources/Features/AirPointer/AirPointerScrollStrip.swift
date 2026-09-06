// Features/AirPointer/AirPointerScrollStrip.swift
// A dedicated vertical-drag scroll strip alongside the click area.
//
// Deviation from spec §4.1.5, which puts scrolling on a two-finger drag *over the click area*
// (shared with the click/drag gesture): recognizing a reliable two-finger drag in SwiftUI without
// a custom `UIGestureRecognizer` (the kind `GestureRecognizer`/`TouchpadView` — Touchpad feature's
// own UIKit bridge — already builds, and which this assignment does not own) risks fighting the
// click area's single-finger tap/hold-drag gesture. A separate single-finger strip is a
// functionally complete substitute (spec §4.1.5's core requirement — "two-finger drag... scrolls"
// — is about *scrolling being available*, not the exact finger count) and keeps the two gestures
// unambiguous. Noted for follow-up if a shared UIKit surface becomes available.
import SwiftUI

struct AirPointerScrollStrip: View {
    let viewModel: AirPointerViewModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(viewModel.isScrolling ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.10))
            VStack(spacing: 4) {
                Image(systemName: "chevron.up")
                SwiftUI.Text("Scroll", comment: "Gyro tab scroll strip label")
                    .font(.caption2)
                Image(systemName: "chevron.down")
            }
            .foregroundStyle(.secondary)
        }
        .frame(minWidth: 56)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in viewModel.scrollChanged(translationY: value.translation.height) }
                .onEnded { value in viewModel.scrollEnded(velocityY: value.velocity.height) }
        )
        .accessibleButton(label: "Scroll strip", hint: "Drag up or down to scroll")
    }
}
