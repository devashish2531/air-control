import Testing
@testable import AirMouseFilters

@Suite struct DisplayClampTests {
    // Two side-by-side displays with a vertical-offset gap between them, mimicking real multi-monitor
    // setups that don't tile perfectly:
    //   left:  (0,0)-(1920,1080)
    //   right: (1920,200)-(3840,1280)   (top edge offset down by 200pt from the left display)
    static let left = DisplayRect(frame: Rect(x: 0, y: 0, width: 1920, height: 1080))
    static let right = DisplayRect(frame: Rect(x: 1920, y: 200, width: 1920, height: 1080))
    static let clamp = DisplayClamp(displays: [left, right])

    @Test func targetInsideADisplayIsAccepted() {
        let target = Point(x: 500, y: 500)
        #expect(Self.clamp.clamp(target: target, current: Point(x: 100, y: 100)) == target)
    }

    @Test func targetInsideSecondDisplayIsAccepted() {
        let target = Point(x: 2500, y: 700)
        #expect(Self.clamp.clamp(target: target, current: Point(x: 2000, y: 700)) == target)
    }

    @Test func targetInGapClampsIntoCurrentDisplay() {
        // (1950, 50) is within the right display's X range but above its top edge (y=200), and it's
        // not inside the left display either (x > 1920) — classic "gap" position.
        let target = Point(x: 1950, y: 50)
        let current = Point(x: 1800, y: 50) // currently on the left display
        let result = Self.clamp.clamp(target: target, current: current)
        #expect(Self.left.frame.contains(result))
    }

    @Test func targetInGapClampsIntoRightDisplayWhenCurrentIsThere() {
        let target = Point(x: 1950, y: 50)
        let current = Point(x: 2000, y: 300) // currently on the right display
        let result = Self.clamp.clamp(target: target, current: current)
        #expect(Self.right.frame.contains(result))
    }

    @Test func recenterJumpsToCenterOfCurrentDisplay() {
        let current = Point(x: 500, y: 500)
        let center = Self.clamp.recenterPosition(current: current)
        #expect(center == Self.left.frame.center)
    }

    @Test func recenterReturnsNilWhenCurrentIsNowhere() {
        let clamp = DisplayClamp(displays: [Self.left])
        let farAway = Point(x: -1000, y: -1000)
        #expect(clamp.recenterPosition(current: farAway) == nil)
    }

    @Test func displayContainingFindsCorrectDisplay() {
        #expect(Self.clamp.display(containing: Point(x: 100, y: 100))?.frame == Self.left.frame)
        #expect(Self.clamp.display(containing: Point(x: 3000, y: 700))?.frame == Self.right.frame)
    }

    @Test func farOutOfBoundsTargetWithUnknownCurrentFallsBackToNearestDisplay() {
        let clamp = DisplayClamp(displays: [Self.left, Self.right])
        let target = Point(x: -500, y: -500)
        let current = Point(x: -9999, y: -9999) // not on any display
        let result = clamp.clamp(target: target, current: current)
        #expect(Self.left.frame.contains(result) || Self.right.frame.contains(result))
    }

    @Test func rectClampedClampsEachAxisIndependently() {
        let rect = Rect(x: 0, y: 0, width: 100, height: 100)
        #expect(rect.clamped(Point(x: -10, y: 50)) == Point(x: 0, y: 50))
        #expect(rect.clamped(Point(x: 50, y: 200)) == Point(x: 50, y: 100))
        #expect(rect.clamped(Point(x: 50, y: 50)) == Point(x: 50, y: 50))
    }

    @Test func rectContainsBoundaryInclusive() {
        let rect = Rect(x: 0, y: 0, width: 100, height: 100)
        #expect(rect.contains(Point(x: 0, y: 0)))
        #expect(rect.contains(Point(x: 100, y: 100)))
        #expect(!rect.contains(Point(x: 100.1, y: 0)))
    }

    @Test func singleDisplayClampsFullyOutOfBoundsTarget() {
        let clamp = DisplayClamp(displays: [Self.left])
        let target = Point(x: -500, y: 5000)
        let result = clamp.clamp(target: target, current: Point(x: 10, y: 10))
        #expect(result == Point(x: 0, y: 1080))
    }
}
