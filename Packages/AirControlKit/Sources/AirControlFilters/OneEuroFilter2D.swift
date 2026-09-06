import Foundation

/// A convenience wrapper running two independent `OneEuroFilter`s, one per axis, for smoothing a
/// `Vector2` signal (e.g. a touch position) with the same parameters on both axes.
public struct OneEuroFilter2D: Sendable {
    public var x: OneEuroFilter
    public var y: OneEuroFilter

    public init(minCutoff: Double, beta: Double, dCutoff: Double = 1.0) {
        self.x = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
        self.y = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
    }

    public mutating func filter(_ v: Vector2, t: TimeInterval) -> Vector2 {
        Vector2(x: x.filter(v.x, t: t), y: y.filter(v.y, t: t))
    }

    public mutating func reset() {
        x.reset()
        y.reset()
    }
}
