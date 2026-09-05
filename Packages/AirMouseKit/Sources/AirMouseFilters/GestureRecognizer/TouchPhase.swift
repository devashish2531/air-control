/// Mirrors `UITouch.Phase`'s cases relevant to gesture recognition, without depending on UIKit.
public enum TouchPhase: Sendable, Equatable {
    case began
    case moved
    case stationary
    case ended
    case cancelled
}
