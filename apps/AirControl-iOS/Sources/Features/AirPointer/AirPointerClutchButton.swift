// Features/AirPointer/AirPointerClutchButton.swift
// spec §4.1.5: "bottom = Clutch button ≥ 96 pt, thumb position (mirrored for left-handed)."
// spec §4.3.6: hold (press-and-hold to move) or toggle, per setting; double-tap → recenter
// (handled by `AirPointerViewModel.clutchPressEnded()`'s debounce).
import AirControlFilters
import SwiftUI

struct AirPointerClutchButton: View {
    let viewModel: AirPointerViewModel
    let engineState: GyroEngineState

    /// spec §11.3 / §4.1.5: "Clutch button ≥ 96 pt".
    static let minimumSize: CGFloat = 96

    var body: some View {
        ZStack {
            Circle()
                .fill(fillStyle)
            Circle()
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            Image(systemName: "hand.point.up.braille.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(minWidth: Self.minimumSize, minHeight: Self.minimumSize)
        .contentShape(Circle())
        .scaleEffect(isActive ? 0.96 : 1)
        .animation(ReduceMotion.isEnabled ? nil : .easeOut(duration: 0.12), value: isActive)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in viewModel.clutchPressBegan() }
                .onEnded { _ in viewModel.clutchPressEnded() }
        )
        .accessibleButton(
            label: LocalizedStringKey(viewModel.engine.clutchMode == .hold ? "Clutch, hold to move" : "Clutch, tap to toggle"),
            hint: "Double-tap to recenter"
        )
        .accessibleLatched(isActive)
    }

    private var isActive: Bool { engineState == .armed || engineState == .moving }

    private var fillStyle: Color {
        switch engineState {
        case .moving: return .green
        case .armed: return .accentColor
        default: return .accentColor.opacity(0.55)
        }
    }
}
