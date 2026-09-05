import Foundation

/// Scroll pixel scaling (spec §3.6.1, §3.6.4, §5.3.4):
///
/// `px = pt · scrollGain(scrollSpeed) · (natural ? −1 : 1)` where `scrollGain(1…10)` is geometric
/// from 0.5 to 3.0.
public struct ScrollGain: Sendable {
    /// Scroll speed slider, 1...10 (spec default 5).
    public var scrollSpeed: Double
    /// Natural-scroll sign flip: inverts both axes so content follows the finger (spec §3.6.4's
    /// single `invertForNatural` boolean switch).
    public var invertForNatural: Bool

    public init(scrollSpeed: Double = 5, invertForNatural: Bool = false) {
        self.scrollSpeed = scrollSpeed
        self.invertForNatural = invertForNatural
    }

    /// spec §3.6.1: geometric 0.5...3.0 over scroll speed 1...10.
    public static func gain(speed: Double) -> Double {
        let clamped = Swift.min(Swift.max(speed, 1), 10)
        return 0.5 * pow(3.0 / 0.5, (clamped - 1) / 9)
    }

    public var gain: Double { Self.gain(speed: scrollSpeed) }

    /// Converts a wire scroll delta (i16 eighth-point finger-travel units, spec §3.5.2) into host
    /// pixels: divides by 8, applies speed gain, then the natural-scroll sign.
    public func pixels(fromEighthPointDelta eighthPt: Delta) -> Delta {
        pixels(fromPointDelta: Delta(dx: eighthPt.dx / 8.0, dy: eighthPt.dy / 8.0))
    }

    /// Same conversion when the delta is already in points rather than wire eighth-point units.
    public func pixels(fromPointDelta pt: Delta) -> Delta {
        let sign = invertForNatural ? -1.0 : 1.0
        return Delta(dx: pt.dx * gain * sign, dy: pt.dy * gain * sign)
    }
}
