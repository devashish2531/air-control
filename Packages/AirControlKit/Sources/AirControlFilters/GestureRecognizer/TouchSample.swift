import Foundation

/// One touch's state at one moment, abstracted away from `UITouch` so this module has no UIKit
/// dependency. A `TouchpadView` feeds these straight from `touchesBegan/Moved/Ended/Cancelled` (spec
/// §4.2.1), one `TouchSample` per touch in the callback's touch set.
public struct TouchSample: Sendable, Equatable {
    public let id: TouchID
    public let phase: TouchPhase
    public let position: Point
    public let timestamp: TimeInterval
    /// Touch major-axis radius in points, for palm rejection (spec §4.2.6: reject if > 30 pt).
    public let majorRadius: Double
    public let kind: TouchKind

    public init(
        id: TouchID,
        phase: TouchPhase,
        position: Point,
        timestamp: TimeInterval,
        majorRadius: Double = 0,
        kind: TouchKind = .finger
    ) {
        self.id = id
        self.phase = phase
        self.position = position
        self.timestamp = timestamp
        self.majorRadius = majorRadius
        self.kind = kind
    }
}
