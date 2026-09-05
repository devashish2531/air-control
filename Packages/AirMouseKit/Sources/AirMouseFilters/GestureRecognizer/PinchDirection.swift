/// spec §4.2.5: pinch (keys mode) emits one zoom step per `pinchThreshold` (40 pt) of inter-finger
/// distance change.
public enum PinchDirection: Sendable, Equatable {
    case zoomIn
    case zoomOut
}
