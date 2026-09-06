// Features/AirPointer/AirPointerUnsupportedView.swift
// spec §4.1.5: "If no gyro: tab hidden; Settings › Gyro shows 'This device has no gyroscope.'"
// `RootTabView` already hides the tab via `GyroEngineProviding.isGyroAvailable`; this is the
// defensive fallback if the screen is reached anyway (direct navigation, tests, or before the
// real `GyroEngine` is wired into `AppEnvironment` — see `AirPointerFeature.swift`'s integration
// note).
import SwiftUI

struct AirPointerUnsupportedView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gyroscope")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            SwiftUI.Text("This device has no gyroscope.", comment: "Gyro tab / Settings unsupported-device message, spec 4.1.5")
                .font(.headline)
                .multilineTextAlignment(.center)
            SwiftUI.Text("Air Pointer needs a gyroscope to turn your phone's motion into cursor movement.", comment: "Gyro tab unsupported-device explanation")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .airControlDynamicTypeRange()
        .accessibilityElement(children: .combine)
    }
}
