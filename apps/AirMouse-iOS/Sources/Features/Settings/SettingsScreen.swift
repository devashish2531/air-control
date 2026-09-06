// Features/Settings/SettingsScreen.swift
// Settings per spec §4.1.9 / §11.3 constants. This covers the fields explicitly listed in this
// agent's assignment (pointer sensitivity/acceleration, natural scroll, momentum, tap-to-click,
// drag-lock, gyro sensitivity/smoothing, haptics toggles, keep-screen-awake, Labs prediction,
// Diagnostics entry, About) rather than every row of spec §4.1.9's full table — the remaining
// rows (Gestures timing constants, Keyboard passthrough, Remote, Macs per-host overrides,
// Appearance, Tutorial replay, Export/Import) are left for the owning feature agents to add to
// this screen or their own, since several reference types (per-host overrides, shortcut palette)
// aren't owned by this module.

import SwiftUI
import Observation

public struct SettingsScreen: View {
    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        SettingsForm(environment: environment)
            .navigationTitle(Text("Settings", comment: "Settings screen navigation title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", comment: "Settings: dismisses the screen")
                    }
                }
            }
    }
}

private struct SettingsForm: View {
    @Bindable var userSettings: UserSettings
    @Bindable var labs: Labs
    let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        self._userSettings = Bindable(wrappedValue: environment.userSettings)
        self._labs = Bindable(wrappedValue: environment.labs)
    }

    var body: some View {
        Form {
            appearanceSection
            pointerSection
            gesturesSection
            gyroSection
            feedbackSection
            labsSection
            diagnosticsSection
            aboutSection
        }
        .airMouseDynamicTypeRange()
    }

    // MARK: Appearance (docs/08 §4: Appearance picker, first section, takes effect immediately
    // since `RootTabView` reads `userSettings.snapshot.appearance.mode.colorScheme` from this
    // same `@Observable` snapshot — no extra plumbing needed here.)

    private var appearanceSection: some View {
        Section {
            Picker(selection: $userSettings.snapshot.appearance.mode) {
                ForEach(AppearanceMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            } label: {
                Text("Appearance", comment: "Settings › Appearance: System/Light/Dark picker label")
            }
        } header: {
            Text("Appearance", comment: "Settings section header")
        }
    }

    // MARK: Pointer (spec §4.1.9 "Pointer")

    private var pointerSection: some View {
        Section {
            Stepper(value: $userSettings.snapshot.pointer.sensitivity, in: PointerSettings.sensitivityRange) {
                LabeledContent {
                    Text("\(userSettings.snapshot.pointer.sensitivity)")
                } label: {
                    Text("Sensitivity", comment: "Settings › Pointer: sensitivity control label")
                }
            }
            .accessibilityValue(Text("\(userSettings.snapshot.pointer.sensitivity) of 10"))

            Picker(selection: $userSettings.snapshot.pointer.acceleration) {
                ForEach(PointerAcceleration.allCases) { option in
                    Text(option.title).tag(option)
                }
            } label: {
                Text("Acceleration", comment: "Settings › Pointer: acceleration picker label")
            }
        } header: {
            Text("Pointer", comment: "Settings section header")
        }
    }

    // MARK: Gestures (subset: natural scroll, momentum, tap-to-click, drag lock)

    private var gesturesSection: some View {
        Section {
            Toggle(isOn: $userSettings.snapshot.gestures.tapToClick) {
                Text("Tap to click", comment: "Settings › Gestures toggle")
            }
            Toggle(isOn: $userSettings.snapshot.gestures.dragLock) {
                Text("Drag lock", comment: "Settings › Gestures toggle")
            }
            Picker(selection: $userSettings.snapshot.gestures.naturalScroll) {
                ForEach(ScrollDirectionSetting.allCases) { option in
                    Text(option.title).tag(option)
                }
            } label: {
                Text("Scroll direction", comment: "Settings › Gestures picker label")
            }
            Toggle(isOn: $userSettings.snapshot.gestures.momentum) {
                Text("Momentum", comment: "Settings › Gestures toggle")
            }
        } header: {
            Text("Gestures", comment: "Settings section header")
        }
    }

    // MARK: Gyro (subset: sensitivity, smoothing)

    private var gyroSection: some View {
        Section {
            Stepper(value: $userSettings.snapshot.gyro.sensitivity, in: GyroSettings.sensitivityRange) {
                LabeledContent {
                    Text("\(userSettings.snapshot.gyro.sensitivity)")
                } label: {
                    Text("Sensitivity", comment: "Settings › Gyro: sensitivity control label")
                }
            }
            Stepper(value: $userSettings.snapshot.gyro.smoothing, in: GyroSettings.smoothingRange) {
                LabeledContent {
                    Text("\(userSettings.snapshot.gyro.smoothing)")
                } label: {
                    Text("Smoothing", comment: "Settings › Gyro: smoothing control label")
                }
            }
            if !environment.gyro.isGyroAvailable {
                Text(AppError.gyroUnavailable.presentation.title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Gyro", comment: "Settings section header")
        }
    }

    // MARK: Feedback (haptics, sounds, keep screen awake)

    private var feedbackSection: some View {
        Section {
            Toggle(isOn: $userSettings.snapshot.feedback.hapticsEnabled) {
                Text("Haptics", comment: "Settings › Feedback toggle")
            }
            Toggle(isOn: $userSettings.snapshot.feedback.soundsEnabled) {
                Text("Sounds", comment: "Settings › Feedback toggle")
            }
            Toggle(isOn: $userSettings.snapshot.feedback.keepScreenAwake) {
                Text("Keep screen awake", comment: "Settings › Feedback toggle")
            }
            .onChange(of: userSettings.snapshot.feedback.keepScreenAwake) { _, newValue in
                environment.idleTimer.isEnabledBySettings = newValue
            }
        } header: {
            Text("Feedback", comment: "Settings section header")
        } footer: {
            Text("Haptics and sounds fall back to a brief visual pulse on devices without a Taptic Engine.", comment: "Settings › Feedback footer, spec §4.8.1.9")
        }
    }

    // MARK: Labs

    private var labsSection: some View {
        Section {
            Toggle(isOn: $labs.prediction) {
                Text("Pointer prediction", comment: "Settings › Labs toggle")
            }
        } header: {
            Text("Labs", comment: "Settings section header")
        } footer: {
            Text("Experimental features. Off by default.", comment: "Settings › Labs footer")
        }
    }

    // MARK: Diagnostics entry

    private var diagnosticsSection: some View {
        Section {
            NavigationLink {
                DiagnosticsScreen()
            } label: {
                Text("Diagnostics", comment: "Settings: navigates to the Diagnostics screen")
            }
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            LabeledContent {
                Text(Self.appVersion)
            } label: {
                Text("Version", comment: "Settings › About row label")
            }
            if let url = URL(string: "https://github.com/air-mouse/air-mouse") {
                Link(destination: url) {
                    Text("GitHub", comment: "Settings › About: link to the project's GitHub repository")
                }
            }
            LabeledContent {
                Text("MIT")
            } label: {
                Text("License", comment: "Settings › About row label")
            }
        } header: {
            Text("About", comment: "Settings section header")
        }
    }

    private static var appVersion: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(shortVersion) (\(build))"
    }
}

#Preview {
    NavigationStack {
        SettingsScreen()
            .environment(\.appEnvironment, .preview())
    }
}
