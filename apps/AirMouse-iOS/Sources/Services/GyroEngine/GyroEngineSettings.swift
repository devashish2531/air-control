// Services/GyroEngine/GyroEngineSettings.swift
// Construction-time configuration for `GyroEngine`, mirroring `UserSettings.GyroSettings` (spec
// §4.1.9) plus the fields that struct does not yet model (`clutchMode`, `recenterMode`,
// `lockOrientation` — see the deviation note in `GyroEngine.swift`).
import AirMouseFilters
import Foundation

/// Which gestures trigger recenter (spec §4.1.9 "Recenter Double-tap/Shake/Both").
public enum GyroRecenterMode: String, Sendable, Equatable, CaseIterable {
    case doubleTap
    case shake
    case both

    public var respondsToDoubleTap: Bool { self == .doubleTap || self == .both }
    public var respondsToShake: Bool { self == .shake || self == .both }
}

public struct GyroEngineSettings: Sendable, Equatable {
    /// 1...10 (spec §4.3.2).
    public var sensitivity: Double
    /// One-Euro `minCutoff` slider, 0...10 (spec §4.3.4).
    public var smoothingSlider: Double
    /// Degrees/s, 0...3 (spec §4.3.3).
    public var deadZoneDegPerSec: Double
    public var clutchMode: ClutchMode
    public var recenterMode: GyroRecenterMode
    /// spec §4.1.9 "Lock orientation": suspends interface-orientation tracking.
    public var isOrientationLocked: Bool

    public init(
        sensitivity: Double = 5,
        smoothingSlider: Double = 5,
        deadZoneDegPerSec: Double = 0.5,
        clutchMode: ClutchMode = .hold,
        recenterMode: GyroRecenterMode = .both,
        isOrientationLocked: Bool = false
    ) {
        self.sensitivity = sensitivity
        self.smoothingSlider = smoothingSlider
        self.deadZoneDegPerSec = deadZoneDegPerSec
        self.clutchMode = clutchMode
        self.recenterMode = recenterMode
        self.isOrientationLocked = isOrientationLocked
    }
}
