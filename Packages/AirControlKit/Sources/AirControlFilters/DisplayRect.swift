/// One display's bounds in CG global space (spec §5.3.8: `CGGetActiveDisplayList` +
/// `CGDisplayBounds`), expressed with this module's own `Rect` rather than `CGRect`.
public struct DisplayRect: Sendable, Equatable {
    public var frame: Rect

    public init(frame: Rect) {
        self.frame = frame
    }
}
