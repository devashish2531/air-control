/// spec §4.2.5: three-finger swipe direction (Swipes mode), one shot per gesture at
/// `threeFingerSwipeDistance`.
public enum SwipeDirection: Sendable, Equatable {
    case up
    case down
    case left
    case right
}
