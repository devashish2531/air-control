/// One output event from `GestureRecognizer`, shaped close to the wire messages of spec §4.2.5/§3.6
/// so a transport layer can translate these almost directly into `Message` values.
public enum TouchpadIntent: Sendable, Equatable {
    /// Single-finger cursor move, raw finger delta in points (host applies gain/acceleration,
    /// spec §4.2.4).
    case move(Delta)
    case click(button: ClickButton, kind: ClickKind, count: Int)
    /// Purely a UX hint alongside a long-press-triggered right click (spec §4.2.3: "haptic").
    case longPressHaptic
    case dragLockEngaged
    case dragLockDisengaged
    case scrollPhaseBegan
    case scrollChanged(Delta)
    /// `velocity` is the mean of the last 3 frames (spec §4.2.5), points/s.
    case scrollPhaseEnded(velocity: Vector2, momentum: Bool)
    case scrollCancelled
    case swipe(SwipeDirection)
    case pinch(PinchDirection)
    case fourFingerTap
    /// Finger(s) lifted / gesture ended with no further motion expected (spec §3.5.6 `motionEnd`).
    case motionEnd
}
