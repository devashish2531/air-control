// spec §5.2 — single window, 4 steps (Accessibility, Launch at login, Firewall, Pair).
import SwiftUI

struct OnboardingWindow: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: OnboardingViewModel?

    var body: some View {
        Group {
            if let viewModel {
                OnboardingStepper(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        // The "Pair" step (below) embeds `PairingContentView`, whose QR/countdown/status content
        // needs ~610pt of height; 420 was sized only for the first three steps and clipped the Pair
        // step's title/instructions and Next/Done bar off-window, leaving just a blank white QR
        // backdrop visible (spec §5.2 review).
        .frame(width: 480, height: 620)
        .onAppear {
            if viewModel == nil {
                viewModel = OnboardingViewModel(permissions: environment.permissions, settings: environment.settings)
            }
        }
    }
}

private struct OnboardingStepper: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepContent
            Spacer()
            HStack {
                if viewModel.currentStepIndex > 0 {
                    Button("Back") { viewModel.goToPreviousStep() }
                }
                Spacer()
                if viewModel.isLastStep {
                    Button("Done") { viewModel.markCompleted() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Next") { viewModel.goToNextStep() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(viewModel.currentStep == .accessibility && !viewModel.permissions.isAccessibilityTrusted)
                }
            }
        }
        .padding(24)
        .task {
            // Poll every 2 s while onboarding is visible (spec §5.2 FR-MB-003).
            viewModel.permissions.startPolling(interval: .seconds(2))
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                viewModel.accessibilityStatusChanged()
            }
        }
        .onDisappear {
            viewModel.permissions.stopPolling()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .accessibility: AccessibilityStepView(viewModel: viewModel)
        case .launchAtLogin: LaunchAtLoginStepView(viewModel: viewModel)
        case .firewall: FirewallStepView()
        case .pair: PairStepView()
        }
    }
}

private struct AccessibilityStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Accessibility", systemImage: "accessibility")
                .font(.title2.bold())
            Text("Air Mouse needs Accessibility permission to move the cursor and type on your behalf. It never reads your screen or your keystrokes.")
                .fixedSize(horizontal: false, vertical: true)
            if viewModel.permissions.isAccessibilityTrusted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                HStack {
                    Button("Open System Settings") {
                        viewModel.permissions.openSystemSettingsAccessibility()
                    }
                    Button("Request") {
                        viewModel.permissions.requestAccessibility()
                    }
                }
            }
            Divider()
            Text("Dev note: debug builds must be signed with a stable Apple Development identity (Config/Local.xcconfig), or the grant silently stops working after each rebuild. If it gets stuck: `tccutil reset Accessibility <bundle id>` — and keep only one copy of the app around (spec §5.2 A10).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LaunchAtLoginStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Launch at Login", systemImage: "power")
                .font(.title2.bold())
            Toggle("Launch Air Mouse at login", isOn: Binding(
                get: { viewModel.launchAtLoginEnabled },
                set: { viewModel.setLaunchAtLoginEnabled($0) }
            ))
            if viewModel.launchAtLoginRequiresApproval {
                Button("Approve in Login Items") {
                    viewModel.openLoginItemsSettings()
                }
            }
        }
    }
}

private struct FirewallStepView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Firewall", systemImage: "lock.shield")
                .font(.title2.bold())
            Text("Your Mac's firewall is on. The first time a device connects, macOS may ask whether to allow Air Mouse to receive incoming connections — choose Allow.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PairStepView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pair", systemImage: "qrcode")
                .font(.title2.bold())
            Text("Scan this code with the Air Mouse app on your iPhone or iPad.")
            PairingContentView()
        }
    }
}
