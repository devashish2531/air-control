/// Clamps a proposed cursor position into the union of display rects (spec §5.3.8):
///
/// "Clamp rule: if `target` lies inside any display → accept; else clamp `target` into the bounds
/// of the display containing `virtualPos` (prevents disappearing into gaps)." and "`recenter` →
/// `virtualPos = center(display containing virtualPos)`".
///
/// The "disappearing into gaps" case is this type's edge-sticky behavior: a target that lands in a
/// gap between two non-tiling displays snaps to the nearest edge of whichever display the cursor is
/// currently on, rather than jumping to whichever display happens to be geometrically closest.
public struct DisplayClamp: Sendable {
    public var displays: [DisplayRect]

    public init(displays: [DisplayRect]) {
        self.displays = displays
    }

    /// The display (if any) whose bounds contain `point`.
    public func display(containing point: Point) -> DisplayRect? {
        displays.first { $0.frame.contains(point) }
    }

    /// spec §5.3.8 clamp rule.
    public func clamp(target: Point, current: Point) -> Point {
        if displays.contains(where: { $0.frame.contains(target) }) {
            return target
        }
        if let home = display(containing: current) {
            return home.frame.clamped(target)
        }
        // `current` isn't on any known display either (e.g. displays changed underneath us). Fall
        // back to whichever display's clamp lands closest, so the cursor still ends up somewhere
        // sane rather than off in space.
        return nearestClamp(of: target) ?? target
    }

    /// spec §5.3.8 recenter: jump to the center of the display containing `current`, or `nil` if
    /// `current` isn't on any known display.
    public func recenterPosition(current: Point) -> Point? {
        display(containing: current)?.frame.center
    }

    private func nearestClamp(of target: Point) -> Point? {
        guard !displays.isEmpty else { return nil }
        return displays
            .map { $0.frame.clamped(target) }
            .min { distanceSquared($0, target) < distanceSquared($1, target) }
    }

    private func distanceSquared(_ a: Point, _ b: Point) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }
}
