import XCTest

/// Regression for a reported real-device symptom: the app connects, but dragging on the Touchpad
/// surface moves nothing on the Mac, even though the wire protocol itself is fine
/// (`aircontrol-cli move` moves the cursor). That means the phone's touch → `TouchpadUIView` →
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

extension TouchpadMotionPipelineUITests {
    /// Full end-to-end regression for the reported bug, one level deeper than
    /// `testDraggingTheSurfaceIncreasesMotionCounters` above: that test only proves
    /// touches reach `MotionPublisher` (`sentDatagramCount` increases unconditionally, even with
    /// no Mac connected — see this file's own doc comment). This test pairs against a *real*
    /// Mac helper running in `--loopback` mode and asserts datagrams actually arrive there —
    /// i.e. it exercises the exact path (`ConnectionMotionSink.sendMotion` → `ClientSession.
    /// sendMotion` → `NWDatagramChannel`/`ProbeController` fallback → `HostSession` →
    /// `EventInjector`) the counter-only test cannot see past.
    ///
    /// Reads two fixed paths the harness/CI driver writes/launches before this test runs (neither
    /// started by this test itself):
    ///   - `/tmp/am-pair-url.txt`: a fresh, single-use pairing URL (one line, no trailing
    ///     newline is fine) from a helper started with `--loopback --print-pair-url`
    ///     (`AIRCONTROL_PAIR_URL=` printed to its stdout once it opens the pairing window — copy
    ///     just the URL into this file right before running).
    ///   - `/tmp/am-sim.jsonl`: the `AIRCONTROL_LOOPBACK_LOG` path the same helper was launched
    ///     with (`HostFeature.make`'s doc comment) — this test reads that file directly rather
    ///     than through the app under test.
    ///
    /// Deviation from the more obvious "pass `AIRCONTROL_PAIR_URL` as an env var" approach every
    /// other on-device test in this file/`PairingUITests`/`DeviceRegressionUITests` uses: measured
    /// empirically against this project's actual (XcodeGen-generated, no `environmentVariables:`
    /// block) scheme, `TEST_RUNNER_AIRCONTROL_PAIR_URL=...` on the `xcodebuild test`/
    /// `test-without-building` command line never reaches this XCUITest *runner* process's own
    /// environment for an iOS **Simulator** destination — `ProcessInfo.processInfo.environment`
    /// here comes back with zero `AIRCONTROL_*` keys regardless of what's set on the command line,
    /// confirmed with a throwaway `XCTSkip` dump of every such key before writing this. A plain
    /// `FileManager` read of an absolute `/tmp` path, by contrast, verified working (also
    /// empirically, via a throwaway marker file) — the runner process is an ordinary, unsandboxed
    /// process on this same Mac, so it reaches the same `/tmp` the helper (and this test's own
    /// harness script) write to, no simulator-container translation needed. If this project's
    /// scheme ever grows an explicit `environmentVariables:` passthrough (XcodeGen scheme option)
    /// for `TEST_RUNNER_AIRCONTROL_*`, this could switch back to matching the other tests' pattern.
    @MainActor
    func testSwipesReachHelperLoopbackLog() throws {
        let pairURLPath = "/tmp/am-pair-url.txt"
        let logPath = "/tmp/am-sim.jsonl"

        guard let urlData = FileManager.default.contents(atPath: pairURLPath),
              let pairURL = String(data: urlData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pairURL.isEmpty
        else {
            throw XCTSkip("\(pairURLPath) not found/empty; skipping loopback E2E test (see this test's doc comment)")
        }
        guard FileManager.default.fileExists(atPath: logPath) else {
            throw XCTSkip("\(logPath) not found; skipping loopback E2E test (see this test's doc comment)")
        }

        func mouseMovedCount() -> Int {
            guard let data = FileManager.default.contents(atPath: logPath),
                  let text = String(data: data, encoding: .utf8)
            else { return 0 }
            return text.split(separator: "\n", omittingEmptySubsequences: true)
                .filter { $0.contains("\"kind\":\"mouseMoved\"") }
                .count
        }

        let before = mouseMovedCount()

        let app = XCUIApplication()
        // `XCUIApplication.launchEnvironment` is a distinct, documented mechanism from the
        // runner-process `TEST_RUNNER_`/`ProcessInfo` one discussed above — this one reliably
        // reaches the app-under-test's own process regardless of scheme config, since XCTest's
        // test manager daemon injects it directly when launching that process.
        app.launchEnvironment["AIRCONTROL_PAIR_URL"] = pairURL
        addUIInterruptionMonitor(withDescription: "System permission alert") { alert in
            for label in ["Allow", "OK", "Allow While Using App"] {
                let button = alert.buttons[label]
                if button.exists { button.tap(); return true }
            }
            return false
        }
        app.launch()
        app.tap() // trigger any pending interruption monitor

        let skipOnboarding = app.buttons["Skip onboarding"]
        if skipOnboarding.waitForExistence(timeout: 5) {
            skipOnboarding.tap()
        }

        let tabBarButton = app.tabBars.buttons["Touchpad"]
        if tabBarButton.waitForExistence(timeout: 5) {
            tabBarButton.tap()
        } else {
            app.buttons["Touchpad"].firstMatch.tap()
        }

        let debugLabel = app.staticTexts["touchpad.debugMotion"]
        XCTAssertTrue(
            debugLabel.waitForExistence(timeout: 5),
            "touchpad.debugMotion debug label not found — is this a DEBUG build?"
        )

        let connectDeadline = Date().addingTimeInterval(45)
        while Date() < connectDeadline, !debugLabel.label.contains("state=connected") {
            app.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        XCTAssertTrue(
            debugLabel.label.contains("state=connected"),
            "never reached state=connected within 45 s. label=\(debugLabel.label)"
        )

        let surface = app.otherElements["touchpad.surface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 10), "touchpad.surface not found")
        XCTAssertTrue(surface.isHittable, "touchpad.surface exists but is not hittable")

        // ~20 coordinate drags — the exact gesture the owner reported as producing no motion on
        // the Mac, this time against a real (loopback) helper instead of just the local pipeline.
        for i in 0..<20 {
            let startX = 0.2 + Double(i % 5) * 0.02
            let start = surface.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: 0.5))
            let end = surface.coordinate(withNormalizedOffset: CGVector(dx: startX + 0.3, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end)
        }

        let deadline = Date().addingTimeInterval(15)
        var after = mouseMovedCount()
        while Date() < deadline, after - before < 10 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            after = mouseMovedCount()
        }

        let failuresLabel = debugLabel.label
        XCTAssertGreaterThanOrEqual(
            after - before, 10,
            "helper loopback log at \(logPath) gained only \(after - before) mouseMoved line(s) after 20 drags."
                + " debug label: \(failuresLabel)"
        )
    }
}
