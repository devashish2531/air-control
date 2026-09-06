import Foundation

/// An axis-aligned rectangle in the same coordinate space as `Point` (CG global space per spec
/// §5.3.8, but this module has no CoreGraphics dependency, hence the own type).
public struct Rect: Sendable, Equatable {
    public var origin: Point
    public var width: Double
    public var height: Double

    public init(origin: Point, width: Double, height: Double) {
        self.origin = origin
        self.width = width
        self.height = height
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.origin = Point(x: x, y: y)
        self.width = width
        self.height = height
    }

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + width }
    public var maxY: Double { origin.y + height }

    public var center: Point {
        Point(x: origin.x + width / 2, y: origin.y + height / 2)
    }

    public func contains(_ p: Point) -> Bool {
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }

    /// Distance from `p` to the edge of the rect if `p` is inside a margin near an edge, along one
    /// axis at a time. Used by `GestureRecognizer`'s edge-based palm rejection (spec §4.2.6).
    public func distanceToNearestEdge(_ p: Point) -> Double {
        Swift.min(
            Swift.abs(p.x - minX), Swift.abs(p.x - maxX),
            Swift.abs(p.y - minY), Swift.abs(p.y - maxY)
        )
    }

    /// Clamps `p` into this rect.
    public func clamped(_ p: Point) -> Point {
        Point(
            x: Swift.min(Swift.max(p.x, minX), maxX),
            y: Swift.min(Swift.max(p.y, minY), maxY)
        )
    }
}
