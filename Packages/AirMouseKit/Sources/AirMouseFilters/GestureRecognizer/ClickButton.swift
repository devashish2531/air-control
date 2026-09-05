/// Which mouse button an emitted `TouchpadIntent.click` targets (spec §4.2.5, §5.3.3).
public enum ClickButton: Sendable, Equatable {
    case left
    case right
    case middle
}
