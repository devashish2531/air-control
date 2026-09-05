// Tests/TouchInputTests.swift
// `TouchSampleConversion` and `TouchIdentityMap` (Services/TouchInput), tested with fabricated
// data rather than real `UITouch` (which has no public initializer) per this agent's assignment.

import Testing
import Foundation
import AirMouseFilters
@testable import Air_Mouse

@Suite struct TouchSampleConversionTests {
    private func raw(
        touchID: Int = 0,
        phase: TouchPhase = .moved,
        x: Double = 10, y: Double = 20,
        timestamp: TimeInterval = 1.0,
        majorRadius: Double = 5,
        type: RawTouchType = .direct
    ) -> RawTouchSample {
        RawTouchSample(touchID: touchID, phase: phase, x: x, y: y, timestamp: timestamp, majorRadius: majorRadius, type: type)
    }

    @Test func directTouchConvertsToFingerKind() {
        let sample = TouchSampleConversion.touchSample(from: raw(type: .direct))
        #expect(sample?.kind == .finger)
    }

    @Test func pencilTouchConvertsToPencilKindNotIgnored() {
        // spec §4.2.6: "Apple Pencil ... is treated as a one-finger touch", not dropped.
        let sample = TouchSampleConversion.touchSample(from: raw(type: .pencil))
        #expect(sample?.kind == .pencil)
    }

    @Test func indirectTouchesAreIgnored() {
        #expect(TouchSampleConversion.touchSample(from: raw(type: .indirect)) == nil)
        #expect(TouchSampleConversion.touchSample(from: raw(type: .indirectPointer)) == nil)
    }

    @Test func fieldsRoundTripIntoTouchSample() {
        let sample = TouchSampleConversion.touchSample(from: raw(
            touchID: 7, phase: .began, x: 12.5, y: 34.25, timestamp: 2.5, majorRadius: 6.5, type: .direct
        ))
        #expect(sample?.id == TouchID(7))
        #expect(sample?.phase == .began)
        #expect(sample?.position == Point(x: 12.5, y: 34.25))
        #expect(sample?.timestamp == 2.5)
        #expect(sample?.majorRadius == 6.5)
    }
}

@Suite struct TouchIdentityMapTests {
    @Test func sameObjectAlwaysMapsToSameID() {
        var map = TouchIdentityMap()
        let object = ObjectIdentifier(NSObject())
        let first = map.id(for: object)
        let second = map.id(for: object)
        #expect(first == second)
    }

    @Test func distinctObjectsGetDistinctIDs() {
        var map = TouchIdentityMap()
        // Both objects must stay alive (and thus keep distinct addresses) for the whole test —
        // `ObjectIdentifier(NSObject())` alone lets the temporary `NSObject` be deallocated
        // immediately, and ARC is then free to reuse that address for the *next* allocation,
        // which previously made `a` and `b` compare equal.
        let objectA = NSObject()
        let objectB = NSObject()
        let a = ObjectIdentifier(objectA)
        let b = ObjectIdentifier(objectB)
        #expect(map.id(for: a) != map.id(for: b))
    }

    @Test func releaseForgetsTheMapping() {
        var map = TouchIdentityMap()
        let object = ObjectIdentifier(NSObject())
        _ = map.id(for: object)
        #expect(map.count == 1)
        map.release(object)
        #expect(map.count == 0)
    }

    @Test func idsAreAssignedInIncreasingOrder() {
        var map = TouchIdentityMap()
        // See `distinctObjectsGetDistinctIDs`: keep both objects alive so their addresses (and
        // therefore their `ObjectIdentifier`s) can't collide.
        let objectA = NSObject()
        let objectB = NSObject()
        let a = map.id(for: ObjectIdentifier(objectA))
        let b = map.id(for: ObjectIdentifier(objectB))
        #expect(b == a + 1)
    }
}
