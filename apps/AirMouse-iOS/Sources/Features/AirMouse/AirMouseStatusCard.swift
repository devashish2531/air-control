// Features/AirMouse/AirMouseStatusCard.swift
// Top-third status card (spec §4.1.5: "calibration indicator, 'hold like a remote' hint on first
// use"; §4.3.7's 1 s progress ring).
import SwiftUI

struct AirMouseStatusCard: View {
    let engineState: GyroEngineState
    let calibrationProgress: Double
    let isRawFallbackIndicatorVisible: Bool
    let isFirstUse: Bool

    var body: some View {
        VStack(spacing: 8) {
            if engineState == .calibrating {
                calibrationBody
            } else {
                readyBody
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .airMouseDynamicTypeRange()
        .accessibilityElement(children: .combine)
    }

    private var calibrationBody: some View {
        VStack(spacing: 10) {
            ProgressView(value: calibrationProgress)
                .progressViewStyle(.circular)
                .scaleEffect(1.4)
            SwiftUI.Text("Hold the phone like a remote and keep it still", comment: "Gyro calibration instruction, spec 4.3.7")
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
        }
        .accessibilityLabel(SwiftUI.Text("Calibrating, \(Int(calibrationProgress * 100)) percent", comment: "Accessibility label for gyro calibration progress"))
    }

    private var readyBody: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: statusGlyph)
                    .foregroundStyle(statusTint)
                SwiftUI.Text(statusTitle)
                    .font(.subheadline.weight(.semibold))
            }
            if isFirstUse {
                SwiftUI.Text("Hold the phone like a remote and point at your Mac's screen.", comment: "Gyro tab first-use hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if isRawFallbackIndicatorVisible {
                SwiftUI.Text("Calibrating…", comment: "Gyro magnetometer-uncalibrated indicator, spec 4.3.5")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusGlyph: String {
        switch engineState {
        case .idle: return "hand.raised"
        case .armed: return "gyroscope"
        case .moving: return "cursorarrow.motionlines"
        case .calibrating: return "dot.circle.and.cursorarrow"
        }
    }

    private var statusTint: Color {
        switch engineState {
        case .moving: return .green
        case .armed: return .accentColor
        default: return .secondary
        }
    }

    private var statusTitle: LocalizedStringKey {
        switch engineState {
        case .idle: return "Hold the clutch to move the cursor"
        case .armed: return "Ready — move the phone"
        case .moving: return "Moving"
        case .calibrating: return "Calibrating"
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        AirMouseStatusCard(engineState: .idle, calibrationProgress: 0, isRawFallbackIndicatorVisible: false, isFirstUse: true)
        AirMouseStatusCard(engineState: .armed, calibrationProgress: 0, isRawFallbackIndicatorVisible: false, isFirstUse: false)
        AirMouseStatusCard(engineState: .moving, calibrationProgress: 0, isRawFallbackIndicatorVisible: false, isFirstUse: false)
        AirMouseStatusCard(engineState: .calibrating, calibrationProgress: 0.4, isRawFallbackIndicatorVisible: false, isFirstUse: false)
    }
    .padding()
}
