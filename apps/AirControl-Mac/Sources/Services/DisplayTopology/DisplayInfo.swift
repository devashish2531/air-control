// arch §3.3 DisplayTopology; feeds DisplayClamp (owned by the injection agent) and the diagnostics/pointer
// preferences UI in this module.
import CoreGraphics

/// One physical display, in CG global coordinates (spec §5.3's coordinate space; origin conventions match
/// `CGDisplayBounds`).
public struct DisplayInfo: Sendable, Equatable, Identifiable {
    public var id: CGDirectDisplayID
    public var bounds: CGRect
    public var isMain: Bool

    public init(id: CGDirectDisplayID, bounds: CGRect, isMain: Bool) {
        self.id = id
        self.bounds = bounds
        self.isMain = isMain
    }
}
