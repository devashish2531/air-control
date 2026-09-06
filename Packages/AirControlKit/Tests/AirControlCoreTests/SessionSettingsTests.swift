import Testing
@testable import AirControlCore
import AirControlProtocol

@Suite struct SessionSettingsTests {
    @Test func effectiveWithNoOverridesReturnsHostDefaults() {
        let effective = SessionSettings.effective()
        #expect(effective == Settings.defaults)
    }

    @Test func deviceOverrideAppliesOnTopOfDefaults() {
        let patch = SettingsPatch(sensitivity: 8, momentum: false)
        let effective = SessionSettings.effective(deviceOverride: patch)
        #expect(effective.sensitivity == 8)
        #expect(effective.momentum == false)
        #expect(effective.scrollSpeed == Settings.defaults.scrollSpeed) // untouched field
    }

    @Test func sessionSnapshotWinsOverDeviceOverrideAndDefaults() {
        let patch = SettingsPatch(sensitivity: 8)
        var sessionSnapshot = Settings.defaults
        sessionSnapshot.sensitivity = 3
        let effective = SessionSettings.effective(deviceOverride: patch, sessionSettings: sessionSnapshot)
        #expect(effective.sensitivity == 3)
    }

    @Test func mergingPatchLeavesUnsetFieldsAlone() {
        let patch = SettingsPatch(scrollDirection: .natural)
        let merged = SessionSettings.merging(patch, over: .defaults)
        #expect(merged.scrollDirection == .natural)
        #expect(merged.acceleration == Settings.defaults.acceleration)
        #expect(merged.pinchMode == Settings.defaults.pinchMode)
    }

    @Test func emptyPatchIsANoOp() {
        let merged = SessionSettings.merging(.empty, over: .defaults)
        #expect(merged == Settings.defaults)
    }

    @Test func effectiveSettingsDerivesAccelerationProfile() {
        var settings = Settings.defaults
        settings.acceleration = .fast
        settings.sensitivity = 10
        let effective = EffectiveSettings(settings: settings)
        #expect(effective.pointer.profile == .fast)
        #expect(effective.pointer.sensitivity == 10)
    }

    @Test func effectiveSettingsInvertsScrollForNaturalDirection() {
        var settings = Settings.defaults
        settings.scrollDirection = .natural
        let effective = EffectiveSettings(settings: settings)
        #expect(effective.scroll.invertForNatural == true)
    }

    @Test func effectiveSettingsDoesNotInvertForHostOrInvertedDirection() {
        var hostSettings = Settings.defaults
        hostSettings.scrollDirection = .host
        #expect(EffectiveSettings(settings: hostSettings).scroll.invertForNatural == false)

        var invertedSettings = Settings.defaults
        invertedSettings.scrollDirection = .inverted
        #expect(EffectiveSettings(settings: invertedSettings).scroll.invertForNatural == false)
    }

    @Test func effectiveSettingsEqualityIgnoresIrrelevantDifferences() {
        let a = EffectiveSettings(settings: .defaults)
        let b = EffectiveSettings(settings: .defaults)
        #expect(a == b)
    }
}
