import Foundation

/// Timing/distance constants for `GestureRecognizer` (spec §4.2.2, ranges/defaults in §11.3). All
/// fields are `var` so hosts can apply the user's Settings overrides within the documented ranges.
public struct GestureConfig: Sendable, Equatable {
    public var tapMaxDuration: TimeInterval = 0.200
    public var tapMaxMovement: Double = 8
    public var doubleTapInterval: TimeInterval = 0.300
    /// "`count` increments only while consecutive taps are within `doubleTapInterval` **and 16 pt**
    /// of each other" (spec §4.2.3).
    public var doubleTapMaxMovement: Double = 16
    public var maxTapCount: Int = 3
    public var tapAndDragWindow: TimeInterval = 0.300
    public var tapAndDragEnabled: Bool = true
    public var fingerCountSettle: TimeInterval = 0.080
    public var longPressDuration: TimeInterval = 0.500
    /// spec: LongPress is only reachable "held 500 ms, still, **option on**" — i.e. gated by a
    /// setting. Off by default; enable to get `click(right, tap)` + haptic from a long, still hold.
    public var longPressRightClickEnabled: Bool = false
    public var motionSuppressAfterTap: TimeInterval = 0.080
    /// `nil` = drag-lock off.
    public var dragLockTimeout: TimeInterval? = 3.000
    public var scrollAxisLockAngleDegrees: Double = 20
    public var scrollAxisLockDistance: Double = 30
    public var scrollAxisLockEnabled: Bool = true
    public var pinchThreshold: Double = 40
    public var threeFingerSwipeDistance: Double = 60
    public var flingMinVelocity: Double = 300
    /// User setting passed straight through into `TouchpadIntent.scrollPhaseEnded`'s `momentum`
    /// field (spec §3.6.2's wire `scrollPhase{ended, vx, vy, momentum}`); the `flingMinVelocity`
    /// threshold check against the lift velocity is a *host*-side decision (spec §3.6.2), not made
    /// here.
    public var momentumEnabled: Bool = true
    /// Palm rejection (spec §4.2.6).
    public var palmMajorRadius: Double = 30
    public var edgeMargin: Double = 4
    public var maxConcurrentTouches: Int = 4
    /// Bounds of the touch surface, for edge-based palm rejection. `nil` disables that check.
    public var screenBounds: Rect?

    public init() {}
}
