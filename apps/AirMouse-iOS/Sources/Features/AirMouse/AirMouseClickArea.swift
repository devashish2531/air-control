// Features/AirMouse/AirMouseClickArea.swift
// spec §4.1.5: "Click area split left (primary) / right (secondary): tap = click, hold ≥ 250 ms
// = drag while held."
import SwiftUI

struct AirMouseClickArea: View {
    let viewModel: AirMouseViewModel
    /// Mirrors the split for left-handed use (spec §4.1.5).
    let isLeftHanded: Bool

    var body: some View {
        HStack(spacing: 2) {
            if isLeftHanded {
                secondaryButton
                primaryButton
            } else {
                primaryButton
                secondaryButton
            }
        }
        .frame(minHeight: 120)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var primaryButton: some View {
        clickButton(
            isDragging: viewModel.isPrimaryClickDragging,
            title: "Left click",
            accessibilityLabel: "Left click",
            onPressBegan: viewModel.primaryPressBegan,
            onPressEnded: viewModel.primaryPressEnded
        )
    }

    private var secondaryButton: some View {
        clickButton(
            isDragging: viewModel.isSecondaryClickDragging,
            title: "Right click",
            accessibilityLabel: "Right click",
            onPressBegan: viewModel.secondaryPressBegan,
            onPressEnded: viewModel.secondaryPressEnded
        )
    }

    private func clickButton(
        isDragging: Bool,
        title: LocalizedStringKey,
        accessibilityLabel: LocalizedStringKey,
        onPressBegan: @escaping () -> Void,
        onPressEnded: @escaping () -> Void
    ) -> some View {
        ZStack {
            Rectangle()
                .fill(isDragging ? Color.accentColor.opacity(0.28) : Color.secondary.opacity(0.12))
            SwiftUI.Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .minimumTapTarget()
        .gesture(pressGesture(onPressBegan: onPressBegan, onPressEnded: onPressEnded))
        .accessibleButton(label: accessibilityLabel, hint: isDragging ? "Dragging" : nil)
    }

    private func pressGesture(onPressBegan: @escaping () -> Void, onPressEnded: @escaping () -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in onPressBegan() }
            .onEnded { _ in onPressEnded() }
    }
}
