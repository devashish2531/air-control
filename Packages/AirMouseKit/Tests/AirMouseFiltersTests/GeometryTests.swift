import Testing
@testable import AirMouseFilters

@Suite struct Vector2Tests {
    @Test func additionAndSubtraction() {
        let a = Vector2(x: 1, y: 2)
        let b = Vector2(x: 3, y: -1)
        #expect(a + b == Vector2(x: 4, y: 1))
        #expect(a - b == Vector2(x: -2, y: 3))
    }

    @Test func scalarMultiplicationCommutes() {
        let a = Vector2(x: 2, y: 3)
        #expect(a * 2.0 == Vector2(x: 4, y: 6))
        #expect(2.0 * a == a * 2.0)
    }

    @Test func lengthIsEuclidean() {
        let a = Vector2(x: 3, y: 4)
        #expect(a.length == 5)
    }

    @Test func negationFlipsBothAxes() {
        let a = Vector2(x: 1, y: -2)
        #expect(-a == Vector2(x: -1, y: 2))
    }

    @Test func plusEqualsAccumulates() {
        var a = Vector2(x: 1, y: 1)
        a += Vector2(x: 2, y: 3)
        #expect(a == Vector2(x: 3, y: 4))
    }
}

@Suite struct DeltaTests {
    @Test func eighthPointQuantizationRoundTrips() {
        let delta = Delta(dx: 12.375, dy: -4.0) // 12.375 = 99/8
        let (x, y) = delta.eighthPoints
        #expect(x == 99)
        #expect(y == -32)
        let back = Delta.fromEighthPoints(x: x, y: y)
        #expect(back.dx == 12.375)
        #expect(back.dy == -4.0)
    }

    @Test func eighthPointSaturatesAtPositiveMax() {
        let delta = Delta(dx: 100_000, dy: 0)
        let (x, _) = delta.eighthPoints
        #expect(x == Int16.max)
    }

    @Test func eighthPointSaturatesAtNegativeMin() {
        let delta = Delta(dx: -100_000, dy: 0)
        let (x, _) = delta.eighthPoints
        #expect(x == Int16.min)
    }

    @Test func eighthPointRangeConstantsMatchSpec() {
        // spec §3.5.2: i16 LE, 1/8 point, range ±4095.875 pt.
        #expect(Delta.eighthPointMax == 4095.875)
        #expect(Delta.eighthPointMin == -4096.0)
    }

    @Test func lengthMatchesPythagoras() {
        #expect(Delta(dx: 6, dy: 8).length == 10)
    }

    @Test func additionAndScaling() {
        let a = Delta(dx: 1, dy: 2)
        let b = Delta(dx: 3, dy: 4)
        #expect(a + b == Delta(dx: 4, dy: 6))
        #expect(a * 2 == Delta(dx: 2, dy: 4))
    }

    @Test func vectorRoundTrip() {
        let v = Vector2(x: 3, y: -5)
        let d = Delta(v)
        #expect(d.dx == 3 && d.dy == -5)
        #expect(d.vector == v)
    }
}

@Suite struct RectTests {
    @Test func centerIsMidpoint() {
        let rect = Rect(x: 0, y: 0, width: 100, height: 50)
        #expect(rect.center == Point(x: 50, y: 25))
    }

    @Test func distanceToNearestEdgeInsideBounds() {
        let rect = Rect(x: 0, y: 0, width: 100, height: 100)
        #expect(rect.distanceToNearestEdge(Point(x: 2, y: 50)) == 2)
        #expect(rect.distanceToNearestEdge(Point(x: 50, y: 98)) == 2)
    }

    @Test func minMaxAccessors() {
        let rect = Rect(x: 10, y: 20, width: 30, height: 40)
        #expect(rect.minX == 10)
        #expect(rect.minY == 20)
        #expect(rect.maxX == 40)
        #expect(rect.maxY == 60)
    }
}
