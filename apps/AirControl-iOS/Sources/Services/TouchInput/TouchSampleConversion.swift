// Services/TouchInput/TouchSampleConversion.swift
// Pure, UIKit-free conversion from one raw touch observation to `AirControlFilters.TouchSample`
// (spec §4.2.1, §4.2.6). Factored out of `TouchpadUIView` so the mapping — including the palm/
// pencil/indirect classification rules — is unit-testable with plain fabricated values: `UITouch`
// has no public initializer, so tests build a `RawTouchSample` instead (per this agent's
// assignment: "fake UITouch data structs rather than UITouch").
//
// spec §4.2.6: "Apple Pencil (`type == .pencil`) is treated as a one-finger touch with no pressure
// semantics; hover is ignored." `.indirect`/`.indirectPointer` (trackpad/mouse passthrough,
// spec §4.1.10 FR-IP-003) are routed through a separate path (`UIPointerInteraction`/`GCMouse`,
// TODO in `TouchpadUIView`), not the finger gesture state machine, so they convert to `nil` here.

import Foundation
import AirControlFilters

/// Platform-agnostic mirror of `UITouch.TouchType`'s cases relevant to the touchpad surface.
public enum RawTouchType: Sendable, Equatable {
    case direct
    case pencil
    case indirect
    case indirectPointer
}

/// One touch observation (a real `UITouch`, or one of its `coalescedTouches`/`predictedTouches`),
/// reduced to exactly the fields `GestureRecognizer` needs, before `TouchID` assignment. `touchID`
/// is the caller's already-resolved stable id for the underlying physical touch (see
/// `TouchIdentityMap`), not derived here.
public struct RawTouchSample: Sendable, Equatable {
    public var touchID: Int
    public var phase: TouchPhase
    /// Position in points, in the touchpad view's coordinate space (`preciseLocation(in:)`).
    public var x: Double
    public var y: Double
    /// `UITouch.timestamp` / `.precisePreviousLocation`-bearing coalesced touch's `timestamp`.
    public var timestamp: TimeInterval
    /// `UITouch.majorRadius`, in points (spec §4.2.6 palm rejection: reject if > 30 pt).
    public var majorRadius: Double
    public var type: RawTouchType

    public init(
        touchID: Int,
        phase: TouchPhase,
        x: Double,
        y: Double,
        timestamp: TimeInterval,
        majorRadius: Double,
        type: RawTouchType
    ) {
        self.touchID = touchID
        self.phase = phase
        self.x = x
        self.y = y
        self.timestamp = timestamp
        self.majorRadius = majorRadius
        self.type = type
    }
}

public enum TouchSampleConversion {
    /// spec §4.2.6: pencil is a one-finger touch; direct is a finger; indirect/indirectPointer
    /// (system pointer / iPad trackpad passthrough) are not part of the finger gesture surface.
    public static func kind(for type: RawTouchType) -> TouchKind? {
        switch type {
        case .direct: return .finger
        case .pencil: return .pencil
        case .indirect, .indirectPointer: return nil
        }
    }

    /// Converts one raw observation into a `TouchSample`, or `nil` if this touch type does not
    /// participate in the finger gesture state machine (spec §4.2.6).
    public static func touchSample(from raw: RawTouchSample) -> TouchSample? {
        guard let kind = kind(for: raw.type) else { return nil }
        return TouchSample(
            id: TouchID(raw.touchID),
            phase: raw.phase,
            position: Point(x: raw.x, y: raw.y),
            timestamp: raw.timestamp,
            majorRadius: raw.majorRadius,
            kind: kind
        )
    }
}
