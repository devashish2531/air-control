import Foundation

/// `settings` (C→H; on connect and on any change; full snapshot). spec §3.4.5 / §11.1.
public struct Settings: Codable, Sendable, Equatable {
    /// 1–10, default 5.
    public var sensitivity: Int
    public var acceleration: Acceleration
    /// 1–10, default 5.
    public var scrollSpeed: Int
    public var scrollDirection: ScrollDirection
    public var momentum: Bool
    /// 150–600, default 300.
    public var doubleClickIntervalMs: Int
    public var pinchMode: PinchMode
    /// 50–2000, default 500.
    public var textRateCharsPerSec: Int

    public init(
        sensitivity: Int,
        acceleration: Acceleration,
        scrollSpeed: Int,
        scrollDirection: ScrollDirection,
        momentum: Bool,
        doubleClickIntervalMs: Int,
        pinchMode: PinchMode,
        textRateCharsPerSec: Int
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

    /// The spec's defaults for every field (§3.4.5).
    public static let defaults = Settings(
        sensitivity: ProtocolConstants.pointerSensitivityDefault,
        acceleration: .default,
        scrollSpeed: ProtocolConstants.scrollSpeedDefault,
        scrollDirection: .host,
        momentum: true,
        doubleClickIntervalMs: ProtocolConstants.doubleClickIntervalMsDefault,
        pinchMode: .keys,
        textRateCharsPerSec: ProtocolConstants.textRateCharsPerSecDefault
    )
}
