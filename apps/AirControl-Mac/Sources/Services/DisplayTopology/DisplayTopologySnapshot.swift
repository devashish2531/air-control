// Pure value type + math, kept free of AppKit/CoreGraphics live-query calls so it is directly unit
// testable with an injected fake display list (arch §3.3, §8 HostStateSnapshot).
import CoreGraphics

/// Immutable snapshot of the Mac's current display arrangement.
public struct DisplayTopologySnapshot: Sendable, Equatable {
    public var displays: [DisplayInfo]
    public var mainDisplayID: CGDirectDisplayID
    public var unionBounds: CGRect

    public init(displays: [DisplayInfo], mainDisplayID: CGDirectDisplayID, unionBounds: CGRect) {
        self.displays = displays
        self.mainDisplayID = mainDisplayID
        self.unionBounds = unionBounds
    }

    public static let empty = DisplayTopologySnapshot(displays: [], mainDisplayID: 0, unionBounds: .zero)

    /// Builds a snapshot from a display list, computing the union of every display's bounds. Pure and
    /// side-effect free so tests can call it with a fabricated `[DisplayInfo]` (no real displays needed).
    public static func make(from displays: [DisplayInfo]) -> DisplayTopologySnapshot {
        guard !displays.isEmpty else { return .empty }
        let mainID = displays.first(where: \.isMain)?.id ?? displays[0].id
        let union = displays.dropFirst().reduce(displays[0].bounds) { $0.union($1.bounds) }
        return DisplayTopologySnapshot(displays: displays, mainDisplayID: mainID, unionBounds: union)
    }
}
