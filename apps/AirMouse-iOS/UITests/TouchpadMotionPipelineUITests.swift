import XCTest

/// Regression for a reported real-device symptom: the app connects, but dragging on the Touchpad
/// surface moves nothing on the Mac, even though the wire protocol itself is fine
/// (`airmouse-cli move` moves the cursor). That means the phone's touch → `TouchpadUIView` →
/// `TouchpadController` → `MotionPublisher` pipeline itself was suspect, not the network/crypto
/// layer this agent doesn't own.
///
/// This test isolates exactly that pipeline, with no Mac/pairing required: `MotionPublisher.stats`
/// (Services/MotionPublisher, another agent's file) increments on every `enqueue`/`enqueueScroll`
/// call regardless of whether the underlying `MotionDatagramSink` is actually connected to
/// anything (`MotionPublisher.drain()` calls `sink.sendMotion(_:)` and bumps `sentDatagramCount`
/// unconditionally). `TouchpadDebugMotionLabel` (Features/Touchpad, DEBUG-only) surfaces that
/// snapshot, plus `TouchpadController`'s own `debugIntentCount`/`debugMoveIntentCount` and
/// `TouchpadUIViewDebugCounters` (Services/TouchInput), as the `touchpad.debugMotion` accessibility
/// label. If touches never reach `TouchpadUIView`, or its intents never reach
/// `TouchpadController`/`MotionPublisher`, this label's counters stay at zero after a drag — which
/// is exactly the failure mode to catch.
///
/// Investigation note: this test initially "failed" with every counter at zero — but the cause was
/// this test, not the pipeline. A fresh launch always shows the onboarding full-screen cover (spec
/// §4.1.1) on top of the already-instantiated `RootTabView`; the Touchpad tab's accessibility
/// elements exist in the tree underneath it (so `waitForExistence` succeeds) but are not hittable
/// until onboarding is dismissed, so every synthesized touch silently landed on the onboarding
/// cover instead. Once the test dismisses onboarding first, `touchesBegan`/`touchesMoved` fire,
/// intents reach `TouchpadController`, and `MotionPublisher.sentDatagramCount` increases — i.e.
/// the touch → local-datagram pipeline in this agent's two directories is intact. If a real,
/// already-onboarded/paired device still shows no cursor movement, the defect is downstream of
/// `MotionDatagramSink.sendMotion(_:)` (Connection agent's transport/encryption/Mac-helper receive
/// path), not in `Features/Touchpad`/`Services/TouchInput`.
final class TouchpadMotionPipelineUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testDraggingTheSurfaceIncreasesMotionCounters() throws {
        let app = XCUIApplication()
        app.launch()

        let skipOnboarding = app.buttons["Skip onboarding"]
        if skipOnboarding.waitForExistence(timeout: 5) {
            skipOnboarding.tap()
        }

        let tabBarButton = app.tabBars.buttons["Touchpad"]
        if tabBarButton.waitForExistence(timeout: 5) {
            tabBarButton.tap()
        } else {
            // iPad regular-width uses a sidebar List instead of a tab bar.
            app.buttons["Touchpad"].firstMatch.tap()
        }

        let surface = app.otherElements["touchpad.surface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 10), "touchpad.surface not found")
        XCTAssertTrue(surface.isHittable, "touchpad.surface exists but is not hittable — something is covering it")

        let debugLabel = app.staticTexts["touchpad.debugMotion"]
        XCTAssertTrue(
            debugLabel.waitForExistence(timeout: 5),
            "touchpad.debugMotion debug label not found — is this a DEBUG build?"
        )
        let before = debugLabel.label

        // One-finger press-and-drag across the pad — the exact gesture the owner reported as
        // producing no motion on the Mac.
        for _ in 0..<10 {
            surface.swipeRight()
        }
        let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        for _ in 0..<6 {
            start.press(forDuration: 0.15, thenDragTo: end)
        }

        let deadline = Date().addingTimeInterval(3)
        var after = debugLabel.label
        while Date() < deadline, after == before {
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            after = debugLabel.label
        }

        XCTAssertNotEqual(
            after, before,
            "MotionPublisher counters did not change after dragging the touchpad surface. before=\(before) after=\(after)"
        )
        XCTAssertFalse(after.contains("sent=0"), "No datagrams were ever sent after dragging. after=\(after)")
    }
}
