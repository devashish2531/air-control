// Features/AirMouse/AirMouseLocalSettings.swift
// spec §4.1.9's Gyro settings section lists Clutch (Hold/Toggle), Recenter
// (Double-tap/Shake/Both), and Lock orientation alongside Sensitivity/Smoothing/Dead zone —
// but `UserSettings.GyroSettings` (Services/DocumentStore/UserSettings.swift, owned by another
// agent, not modified here per this assignment) only models the latter three. This is a small
// `UserDefaults`-backed store for the missing three so the feature is fully functional standalone;
// once the Settings-owning agent extends `GyroSettings`, this type can be deleted and its callers
// pointed at the real snapshot fields (single source of truth).
import AirMouseFilters
import Foundation
import Observation

@MainActor
@Observable
public final class AirMouseLocalSettings {
    private enum Key {
        static let clutchMode = "am.gyro.local.clutchMode"
        static let recenterMode = "am.gyro.local.recenterMode"
        static let isOrientationLocked = "am.gyro.local.lockOrientation"
    }

    private let defaults: UserDefaults

    public var clutchMode: ClutchMode {
        didSet { defaults.set(clutchMode == .toggle, forKey: Key.clutchMode) }
    }
    public var recenterMode: GyroRecenterMode {
        didSet { defaults.set(recenterMode.rawValue, forKey: Key.recenterMode) }
    }
    public var isOrientationLocked: Bool {
        didSet { defaults.set(isOrientationLocked, forKey: Key.isOrientationLocked) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.clutchMode = defaults.bool(forKey: Key.clutchMode) ? .toggle : .hold
        self.recenterMode = (defaults.string(forKey: Key.recenterMode)).flatMap(GyroRecenterMode.init(rawValue:)) ?? .both
        self.isOrientationLocked = defaults.bool(forKey: Key.isOrientationLocked)
    }
}
