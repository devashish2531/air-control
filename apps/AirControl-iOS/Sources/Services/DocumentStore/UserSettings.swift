// Services/DocumentStore/UserSettings.swift
// Global settings per spec §4.1.9 / AM-ST-01..07, backed by `UserDefaults` with the keys from
// arch §6.2. `am.settings.v1` holds the Codable snapshot (pointer/gestures/gyro/keyboard/remote/
// appearance/feedback); onboarding/tutorial flags, default tab, auto-connect and last host are
// separate top-level keys per arch §6.2 so they can be read without decoding the whole blob.
//
// Per-host overrides (`TrustedHostRecord.overrides`, spec §4.7.3 "effective settings = global ⊕
// per-host patch") are owned by the Devices/Pairing agents; this type only owns the global layer
// and exposes `SettingsSnapshot` so that layering code elsewhere can read/patch it.

import Foundation
import Observation

// MARK: - UserDefaults keys (arch §6.2, iOS rows)

public enum UserDefaultsKey {
    public static let onboardingCompleted = "am.onboardingCompleted"
    public static let tutorialTouchpadDone = "am.tutorial.touchpadDone"
    public static let tutorialGyroDone = "am.tutorial.gyroDone"
    public static let settingsSnapshot = "am.settings.v1"
    public static let shortcutPalette = "am.shortcutPalette"
    public static let defaultTab = "am.defaultTab"
    public static let autoConnectLastHost = "am.autoConnectLastHost"
    public static let lastHostID = "am.lastHostID"
    /// docs/08 §2.4 — hides the "Left click"/"Right click" captions on the touchpad's click
    /// buttons once the user has successfully used them at least once.
    public static let hasUsedClickButtons = "am.hasUsedClickButtons"
}

// MARK: - Value types

public enum PointerAcceleration: String, Codable, CaseIterable, Sendable, Identifiable {
    case off, precise, standard, fast
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .off: return String(localized: "Off", comment: "Pointer acceleration option")
        case .precise: return String(localized: "Precise", comment: "Pointer acceleration option")
        case .standard: return String(localized: "Default", comment: "Pointer acceleration option")
        case .fast: return String(localized: "Fast", comment: "Pointer acceleration option")
        }
    }
}

public enum ScrollDirectionSetting: String, Codable, CaseIterable, Sendable, Identifiable {
    case host, natural, inverted
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .host: return String(localized: "Host", comment: "Scroll direction option")
        case .natural: return String(localized: "Natural", comment: "Scroll direction option")
        case .inverted: return String(localized: "Inverted", comment: "Scroll direction option")
        }
    }
}

public enum KeyboardEntryMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case live, commit
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .live: return String(localized: "Live", comment: "Keyboard entry mode")
        case .commit: return String(localized: "Commit", comment: "Keyboard entry mode")
        }
    }
}

public enum AppearanceMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case light, dark, system
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .light: return String(localized: "Light", comment: "Appearance option")
        case .dark: return String(localized: "Dark", comment: "Appearance option")
        case .system: return String(localized: "System", comment: "Appearance option")
        }
    }
}

public enum Handedness: String, Codable, CaseIterable, Sendable, Identifiable {
    case left, right
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .left: return String(localized: "Left-handed", comment: "Handedness option")
        case .right: return String(localized: "Right-handed", comment: "Handedness option")
        }
    }
}

public struct PointerSettings: Codable, Sendable, Equatable {
    public var sensitivity: Int
    public var acceleration: PointerAcceleration

    public static let sensitivityRange = 1...10

    public init(sensitivity: Int = 5, acceleration: PointerAcceleration = .standard) {
        self.sensitivity = sensitivity
        self.acceleration = acceleration
    }
}

public struct GestureSettings: Codable, Sendable, Equatable {
    public var tapToClick: Bool
    public var tapAndDrag: Bool
    public var dragLock: Bool
    public var naturalScroll: ScrollDirectionSetting
    public var momentum: Bool
    public var scrollSpeed: Int

    public static let scrollSpeedRange = 1...10

    public init(
        tapToClick: Bool = true,
        tapAndDrag: Bool = true,
        dragLock: Bool = false,
        naturalScroll: ScrollDirectionSetting = .natural,
        momentum: Bool = true,
        scrollSpeed: Int = 5
    ) {
        self.tapToClick = tapToClick
        self.tapAndDrag = tapAndDrag
        self.dragLock = dragLock
        self.naturalScroll = naturalScroll
        self.momentum = momentum
        self.scrollSpeed = scrollSpeed
    }
}

public struct GyroSettings: Codable, Sendable, Equatable {
    public var sensitivity: Int
    public var smoothing: Int
    public var deadZoneDegreesPerSecond: Double

    public static let sensitivityRange = 1...10
    public static let smoothingRange = 0...10
    public static let deadZoneRange = 0.0...3.0

    public init(sensitivity: Int = 5, smoothing: Int = 5, deadZoneDegreesPerSecond: Double = 0.5) {
        self.sensitivity = sensitivity
        self.smoothing = smoothing
        self.deadZoneDegreesPerSecond = deadZoneDegreesPerSecond
    }
}

public struct KeyboardSettings: Codable, Sendable, Equatable {
    public var defaultMode: KeyboardEntryMode
    public var returnSends: Bool

    public init(defaultMode: KeyboardEntryMode = .live, returnSends: Bool = false) {
        self.defaultMode = defaultMode
        self.returnSends = returnSends
    }
}

public struct RemoteSettings: Codable, Sendable, Equatable {
    public var presenterIdleDimSeconds: Int
    public var countdownHaptics: Bool

    public static let idleDimRange = 10...120

    public init(presenterIdleDimSeconds: Int = 10, countdownHaptics: Bool = true) {
        self.presenterIdleDimSeconds = presenterIdleDimSeconds
        self.countdownHaptics = countdownHaptics
    }
}

public struct AppearanceSettings: Codable, Sendable, Equatable {
    public var mode: AppearanceMode
    public var handedness: Handedness

    public init(mode: AppearanceMode = .system, handedness: Handedness = .right) {
        self.mode = mode
        self.handedness = handedness
    }
}

public struct FeedbackSettings: Codable, Sendable, Equatable {
    public var hapticsEnabled: Bool
    public var soundsEnabled: Bool
    public var keepScreenAwake: Bool
    public var idleDimSeconds: Int

    public static let idleDimRange = 10...120

    public init(hapticsEnabled: Bool = true, soundsEnabled: Bool = true, keepScreenAwake: Bool = true, idleDimSeconds: Int = 30) {
        self.hapticsEnabled = hapticsEnabled
        self.soundsEnabled = soundsEnabled
        self.keepScreenAwake = keepScreenAwake
        self.idleDimSeconds = idleDimSeconds
    }
}

/// The full Codable snapshot stored under `am.settings.v1` (arch §6.2). Exportable as-is for
/// Settings › Advanced "Export settings (JSON, Files)" (AM-ST-06).
public struct SettingsSnapshot: Codable, Sendable, Equatable {
    public var pointer: PointerSettings
    public var gestures: GestureSettings
    public var gyro: GyroSettings
    public var keyboard: KeyboardSettings
    public var remote: RemoteSettings
    public var appearance: AppearanceSettings
    public var feedback: FeedbackSettings

    public init(
        pointer: PointerSettings = .init(),
        gestures: GestureSettings = .init(),
        gyro: GyroSettings = .init(),
        keyboard: KeyboardSettings = .init(),
        remote: RemoteSettings = .init(),
        appearance: AppearanceSettings = .init(),
        feedback: FeedbackSettings = .init()
    ) {
        self.pointer = pointer
        self.gestures = gestures
        self.gyro = gyro
        self.keyboard = keyboard
        self.remote = remote
        self.appearance = appearance
        self.feedback = feedback
    }

    public static let `default` = SettingsSnapshot()
}

// MARK: - UserSettings

/// `@Observable` façade over `UserDefaults`. Every mutation re-serializes the whole
/// `SettingsSnapshot` to `am.settings.v1` (small document, infrequent writes — no need for a
/// debounced writer).
@MainActor
@Observable
public final class UserSettings {
    private let defaults: UserDefaults

    public var snapshot: SettingsSnapshot {
        didSet { persistSnapshot() }
    }

    public var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: UserDefaultsKey.onboardingCompleted) }
    }
    public var tutorialTouchpadDone: Bool {
        didSet { defaults.set(tutorialTouchpadDone, forKey: UserDefaultsKey.tutorialTouchpadDone) }
    }
    public var tutorialGyroDone: Bool {
        didSet { defaults.set(tutorialGyroDone, forKey: UserDefaultsKey.tutorialGyroDone) }
    }
    public var defaultTab: AppTab {
        didSet { defaults.set(defaultTab.rawValue, forKey: UserDefaultsKey.defaultTab) }
    }
    public var autoConnectLastHost: Bool {
        didSet { defaults.set(autoConnectLastHost, forKey: UserDefaultsKey.autoConnectLastHost) }
    }
    public var lastHostID: String? {
        didSet { defaults.set(lastHostID, forKey: UserDefaultsKey.lastHostID) }
    }
    /// docs/08 §2.4 — set once the touchpad's on-screen click buttons have been used
    /// successfully; the button captions hide once this flips true.
    public var hasUsedClickButtons: Bool {
        didSet { defaults.set(hasUsedClickButtons, forKey: UserDefaultsKey.hasUsedClickButtons) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.snapshot = Self.loadSnapshot(from: defaults)
        self.onboardingCompleted = defaults.bool(forKey: UserDefaultsKey.onboardingCompleted)
        self.tutorialTouchpadDone = defaults.bool(forKey: UserDefaultsKey.tutorialTouchpadDone)
        self.tutorialGyroDone = defaults.bool(forKey: UserDefaultsKey.tutorialGyroDone)
        self.defaultTab = (defaults.string(forKey: UserDefaultsKey.defaultTab)).flatMap { raw in AppTab(rawValue: raw) ?? (raw == "airMouse" ? .airPointer : nil) } ?? .touchpad
        self.autoConnectLastHost = defaults.object(forKey: UserDefaultsKey.autoConnectLastHost) as? Bool ?? true
        self.lastHostID = defaults.string(forKey: UserDefaultsKey.lastHostID)
        self.hasUsedClickButtons = defaults.bool(forKey: UserDefaultsKey.hasUsedClickButtons)
    }

    /// Restores every setting to its documented default (spec §4.1.9 Advanced "Reset to
    /// defaults"), leaving onboarding/tutorial completion and last-host untouched.
    public func resetToDefaults() {
        snapshot = .default
    }

    private func persistSnapshot() {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            Log.settings.error("Failed to encode SettingsSnapshot")
            return
        }
        defaults.set(data, forKey: UserDefaultsKey.settingsSnapshot)
    }

    private static func loadSnapshot(from defaults: UserDefaults) -> SettingsSnapshot {
        guard let data = defaults.data(forKey: UserDefaultsKey.settingsSnapshot),
              let decoded = try? JSONDecoder().decode(SettingsSnapshot.self, from: data) else {
            return .default
        }
        return decoded
    }
}
