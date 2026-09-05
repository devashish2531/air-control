// Tests/UserSettingsTests.swift
// Defaults and ranges for `UserSettings` / `SettingsSnapshot` (spec §4.1.9, §11.3, AM-ST-01..03).

import Testing
import Foundation
@testable import Air_Mouse

@MainActor
@Suite struct UserSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let suiteName = "UserSettingsTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    @Test func defaultSnapshotMatchesSpec() {
        let settings = UserSettings(defaults: freshDefaults())
        #expect(settings.snapshot.pointer.sensitivity == 5)
        #expect(settings.snapshot.pointer.acceleration == .standard)
        #expect(settings.snapshot.gestures.tapToClick == true)
        #expect(settings.snapshot.gestures.dragLock == false)
        #expect(settings.snapshot.gestures.scrollSpeed == 5)
        #expect(settings.snapshot.gyro.sensitivity == 5)
        #expect(settings.snapshot.gyro.smoothing == 5)
        #expect(settings.snapshot.gyro.deadZoneDegreesPerSecond == 0.5)
        #expect(settings.snapshot.keyboard.defaultMode == .live)
        #expect(settings.snapshot.keyboard.returnSends == false)
        #expect(settings.snapshot.remote.presenterIdleDimSeconds == 10)
        #expect(settings.snapshot.remote.countdownHaptics == true)
        #expect(settings.snapshot.feedback.hapticsEnabled == true)
        #expect(settings.snapshot.feedback.soundsEnabled == true)
        #expect(settings.snapshot.feedback.keepScreenAwake == true)
        #expect(settings.snapshot.feedback.idleDimSeconds == 30)
    }

    @Test func defaultFlagsMatchArch() {
        let settings = UserSettings(defaults: freshDefaults())
        #expect(settings.onboardingCompleted == false)
        #expect(settings.tutorialTouchpadDone == false)
        #expect(settings.tutorialGyroDone == false)
        #expect(settings.defaultTab == .touchpad)
        #expect(settings.autoConnectLastHost == true)
        #expect(settings.lastHostID == nil)
    }

    @Test func constantRangesMatchSpecAppendix() {
        #expect(PointerSettings.sensitivityRange == 1...10)
        #expect(GestureSettings.scrollSpeedRange == 1...10)
        #expect(GyroSettings.sensitivityRange == 1...10)
        #expect(GyroSettings.smoothingRange == 0...10)
        #expect(GyroSettings.deadZoneRange == 0.0...3.0)
        #expect(RemoteSettings.idleDimRange == 10...120)
        #expect(FeedbackSettings.idleDimRange == 10...120)
    }

    @Test func mutationPersistsAcrossInstances() {
        let defaults = freshDefaults()
        let first = UserSettings(defaults: defaults)
        first.snapshot.pointer.sensitivity = 9
        first.snapshot.feedback.hapticsEnabled = false
        first.onboardingCompleted = true
        first.defaultTab = .keyboard

        let second = UserSettings(defaults: defaults)
        #expect(second.snapshot.pointer.sensitivity == 9)
        #expect(second.snapshot.feedback.hapticsEnabled == false)
        #expect(second.onboardingCompleted == true)
        #expect(second.defaultTab == .keyboard)
    }

    @Test func resetToDefaultsRestoresSnapshotOnly() {
        let defaults = freshDefaults()
        let settings = UserSettings(defaults: defaults)
        settings.snapshot.pointer.sensitivity = 1
        settings.onboardingCompleted = true

        settings.resetToDefaults()

        #expect(settings.snapshot == .default)
        // Reset to defaults (spec §4.1.9 Advanced) does not touch onboarding completion.
        #expect(settings.onboardingCompleted == true)
    }
}
