import Testing
@testable import Air_Control
import CoreGraphics

@Suite struct DisplayTopologyTests {
    @Test func emptyListProducesEmptySnapshot() {
        let snapshot = DisplayTopologySnapshot.make(from: [])
        #expect(snapshot == .empty)
    }

    @Test func singleDisplayUnionEqualsItsOwnBounds() {
        let display = DisplayInfo(id: 1, bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true)
        let snapshot = DisplayTopologySnapshot.make(from: [display])
        #expect(snapshot.unionBounds == display.bounds)
        #expect(snapshot.mainDisplayID == 1)
    }

    @Test func unionSpansTwoAdjacentDisplays() {
        let main = DisplayInfo(id: 1, bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true)
        // A second display placed to the right, in CG global coordinates (spec §5.3 coordinate space).
        let secondary = DisplayInfo(id: 2, bounds: CGRect(x: 1920, y: 0, width: 2560, height: 1440), isMain: false)

        let snapshot = DisplayTopologySnapshot.make(from: [main, secondary])

        #expect(snapshot.mainDisplayID == 1)
        #expect(snapshot.unionBounds == CGRect(x: 0, y: 0, width: 1920 + 2560, height: 1440))
        #expect(snapshot.displays.count == 2)
    }

    @Test func mainDisplayFallsBackToFirstWhenNoneFlaggedMain() {
        let displays = [
            DisplayInfo(id: 5, bounds: CGRect(x: 0, y: 0, width: 800, height: 600), isMain: false),
            DisplayInfo(id: 6, bounds: CGRect(x: 800, y: 0, width: 800, height: 600), isMain: false),
        ]
        let snapshot = DisplayTopologySnapshot.make(from: displays)
        #expect(snapshot.mainDisplayID == 5)
    }
}
