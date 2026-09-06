import Foundation
import AirControlProtocol
import AirControlFilters

/// A partial override of `Settings`, every field optional — used for a per-device persisted
/// override layered under whatever the current session negotiates (arch §3.1: "layering:
/// host defaults ← device overrides ← per-session `Settings` message").
public struct SettingsPatch: Codable, Sendable, Equatable {
    public var sensitivity: Int?
    public var acceleration: Acceleration?
    public var scrollSpeed: Int?
    public var scrollDirection: ScrollDirection?
    public var momentum: Bool?
    public var doubleClickIntervalMs: Int?
    public var pinchMode: PinchMode?
    public var textRateCharsPerSec: Int?

    public init(
        sensitivity: Int? = nil,
        acceleration: Acceleration? = nil,
        scrollSpeed: Int? = nil,
        scrollDirection: ScrollDirection? = nil,
        momentum: Bool? = nil,
        doubleClickIntervalMs: Int? = nil,
        pinchMode: PinchMode? = nil,
        textRateCharsPerSec: Int? = nil
    ) {
        self.sensitivity = sensitivity
        self.acceleration = acceleration
        self.scrollSpeed = scrollSpeed
        self.scrollDirection = scrollDirection
        self.momentum = momentum
        self.doubleClickIntervalMs = doubleClickIntervalMs
        self.pinchMode = pinchMode
        self.textRateCharsPerSec = textRateCharsPerSec
    }

    /// No overrides at all — merging this into any `Settings` is a no-op.
    public static let empty = SettingsPatch()
}

/// Layers a host's default `Settings`, an optional per-device override patch, and an optional
/// current-session `Settings` snapshot (the wire `settings` message, spec §3.4.5: "on connect and
/// on any change; full snapshot") into one effective `Settings`, then converts that into the
/// concrete `AirControlFilters` configuration the host's injection pipeline runs.
public enum SessionSettings: Sendable {
    /// Applies `patch` on top of `base`, field by field.
    public static func merging(_ patch: SettingsPatch, over base: Settings) -> Settings {
        var result = base
        if let sensitivity = patch.sensitivity { result.sensitivity = sensitivity }
        if let acceleration = patch.acceleration { result.acceleration = acceleration }
        if let scrollSpeed = patch.scrollSpeed { result.scrollSpeed = scrollSpeed }
        if let scrollDirection = patch.scrollDirection { result.scrollDirection = scrollDirection }
        if let momentum = patch.momentum { result.momentum = momentum }
        if let doubleClickIntervalMs = patch.doubleClickIntervalMs { result.doubleClickIntervalMs = doubleClickIntervalMs }
        if let pinchMode = patch.pinchMode { result.pinchMode = pinchMode }
        if let textRateCharsPerSec = patch.textRateCharsPerSec { result.textRateCharsPerSec = textRateCharsPerSec }
        return result
    }

    /// The full layering: host defaults ← device override ← current session snapshot. A
    /// `sessionSettings` snapshot, when present, is always a *complete* `Settings` (the wire
    /// message is never partial, spec §3.4.5), so it wins outright over the layered
    /// defaults+override rather than being merged field-by-field.
    public static func effective(
        hostDefaults: Settings = .defaults,
        deviceOverride: SettingsPatch = .empty,
        sessionSettings: Settings? = nil
    ) -> Settings {
        if let sessionSettings { return sessionSettings }
        return merging(deviceOverride, over: hostDefaults)
    }
}

/// The concrete filter configuration derived from an effective `Settings`, ready for the host's
/// `EventInjector`/`MotionPipeline` (spec §5.4, §3.6.1). `AirControlCore` only translates settings
/// into filter parameters; it never runs the filters itself (that stays app-side, per-datagram).
public struct EffectiveSettings: Sendable {
    public var pointer: AccelerationCurve
    public var scroll: ScrollGain
    public var momentum: Bool
    public var pinchMode: PinchMode
    public var doubleClickIntervalMs: Int
    public var textRateCharsPerSec: Int

    public init(settings: Settings) {
        pointer = AccelerationCurve(
            sensitivity: Double(settings.sensitivity),
            profile: Self.profile(for: settings.acceleration),
            referenceVelocity: ProtocolConstants.accelerationCurveVRefPointsPerSecond
        )
        scroll = ScrollGain(
            scrollSpeed: Double(settings.scrollSpeed),
            invertForNatural: settings.scrollDirection == .natural
        )
        momentum = settings.momentum
        pinchMode = settings.pinchMode
        doubleClickIntervalMs = settings.doubleClickIntervalMs
        textRateCharsPerSec = settings.textRateCharsPerSec
    }

    private static func profile(for acceleration: Acceleration) -> AccelerationCurve.Profile {
        switch acceleration {
        case .off: .off
        case .precise: .precise
        case .default: .default
        case .fast: .fast
        }
    }
}

extension EffectiveSettings: Equatable {
    /// Manual `Equatable`: compares the fields this module derived rather than relying on
    /// `AccelerationCurve`/`ScrollGain` conforming to `Equatable` themselves — those types are
    /// owned by `AirControlFilters`, and a retroactive `extension ... Equatable` here would risk a
    /// duplicate-conformance clash if another module independently added the same one (the same
    /// hazard noted on `TrustedDeviceRecord`'s `Fingerprint` handling).
    public static func == (lhs: EffectiveSettings, rhs: EffectiveSettings) -> Bool {
        lhs.pointer.sensitivity == rhs.pointer.sensitivity
            && lhs.pointer.profile == rhs.pointer.profile
            && lhs.pointer.referenceVelocity == rhs.pointer.referenceVelocity
            && lhs.scroll.scrollSpeed == rhs.scroll.scrollSpeed
            && lhs.scroll.invertForNatural == rhs.scroll.invertForNatural
            && lhs.momentum == rhs.momentum
            && lhs.pinchMode == rhs.pinchMode
            && lhs.doubleClickIntervalMs == rhs.doubleClickIntervalMs
            && lhs.textRateCharsPerSec == rhs.textRateCharsPerSec
    }
}
