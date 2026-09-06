import XCTest

/// On-device end-to-end regression: touchpad → keyboard → remote → macros → background/foreground
/// → settings, run against a real, already-paired Mac helper (see scripts/device-regression/run.sh).
///
/// Each test independently launches the app and waits for a trusted reconnect to "connected"
/// (the phone is already paired, so this is the normal cold-launch path — no AIRMOUSE_PAIR_URL
/// needed). XCTest runs test methods within a class in ascending method-name order, so methods are
/// prefixed testA_/testB_/... to fix the run order the coordinating shell script expects:
///   xcodebuild test-without-building ... -only-testing:AirMouseUITests/DeviceRegressionUITests
final class DeviceRegressionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
    }

    // MARK: - Shared launch / connect helper

    /// Launches a fresh app instance, arms the Local Network permission interruption monitor, and
    /// blocks (polling, tapping to surface any pending system alert) until the DEBUG
    /// `debug.pairingProgress` label reports `state=connected(...)`, or `timeout` elapses.
    @MainActor
    @discardableResult
    private func launchAndWaitForConnected(timeout: TimeInterval = 45) -> XCUIApplication {
        let app = XCUIApplication()
        self.app = app
        // Test hook: pair from a launch URL when provided (simulator has no persistent identity).
        if let url = ProcessInfo.processInfo.environment["AIRMOUSE_PAIR_URL"], !url.isEmpty {
            app.launchEnvironment["AIRMOUSE_PAIR_URL"] = url
        }
        addUIInterruptionMonitor(withDescription: "System permission alert") { alert in
            for label in ["Allow", "OK", "Allow While Using App"] {
                let button = alert.buttons[label]
                if button.exists { button.tap(); return true }
            }
            return false
        }
        app.launch()

        // KNOWN PRODUCT GAP (see report): a plain cold launch never calls
        // `ConnectionManager.connect()`/`startBrowsing()` on its own --
        // `AppEnvironment.live()`'s own doc comment says browsing/connect only start "when a
        // view calls startBrowsing()/connect()/start() on appear", and the only such call sites
        // are `OnboardingModel` (first-run pairing) and `DevicesScreen.onAppear` (manual "Devices"
        // sheet). Spec §3.3 wants a plain launch to auto-reconnect to the remembered Mac; until
        // that's wired up, this test drives the same path a real user would today -- open
        // Devices (which calls `startBrowsing()` and lets `maybeAutoConnect` fire) -- rather than
        // waiting forever on a `state=connected` that a bare launch will never reach.
        let connectionPill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Connection:'")).firstMatch
        if connectionPill.waitForExistence(timeout: 10) {
            connectionPill.tap()
        }

        // Best-effort explicit tap on the trusted host row: `startBrowsing()`'s own
        // `maybeAutoConnect` only fires for `knownHosts.lastUsedHostFingerprintHex` -- if that
        // pointer was ever repointed at some other transient/foreign pairing (e.g. a stray
        // helper instance on a shared Mac), the real trusted Mac can sit at "Available" forever
        // without this nudge. Tapping the row calls `connectToKnownHost` directly, bypassing
        // that ambiguity. Harmless / a no-op once already connected.
        if app.navigationBars["Devices"].waitForExistence(timeout: 5) {
            // `.firstMatch` (not a single-element subscript): a discovered-but-not-yet-resolved
            // host can transiently appear in both the "Your Macs" and "Other Macs" sections,
            // which would otherwise crash this lookup with "multiple matching elements found".
            let namedRow = app.staticTexts["Devashish’s MacBook Air"].firstMatch
            if namedRow.waitForExistence(timeout: 5) {
                namedRow.tap()
            } else if app.cells.count > 1 {
                app.cells.element(boundBy: 1).tap()
            }
        }

        let connected = waitForConnected(app, timeout: timeout)

        // Interactive-dismiss the Devices sheet. Swiping down over the navigation bar (rather
        // than over the List content, which just scrolls/bounces) reliably triggers SwiftUI's
        // sheet dismissal gesture.
        let devicesBar = app.navigationBars["Devices"]
        if devicesBar.waitForExistence(timeout: 2) {
            devicesBar.swipeDown()
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            if app.navigationBars["Devices"].exists {
                app.swipeDown()
                RunLoop.current.run(until: Date().addingTimeInterval(1))
            }
        }

        XCTAssertTrue(connected, "Did not reach connected within \(timeout)s. \(debugDetail(app))")
        return app
    }

    /// Polls (tapping periodically to surface the interruption monitor) until
    /// `debug.pairingProgress`'s label contains "state=connected", or `timeout` elapses.
    @MainActor
    @discardableResult
    private func waitForConnected(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let debug = app.staticTexts["debug.pairingProgress"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if debug.exists, debug.label.contains("state=connected") { return true }
            app.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        return debug.exists && debug.label.contains("state=connected")
    }

    /// One-line failure marker: the current debug pairing label (or a placeholder if it's gone).
    @MainActor
    private func debugDetail(_ app: XCUIApplication) -> String {
        let debug = app.staticTexts["debug.pairingProgress"]
        return "debug=\(debug.exists ? debug.label : "(missing)")"
    }

    @MainActor
    private func selectTab(_ title: String, in app: XCUIApplication) {
        let tabBarButton = app.tabBars.buttons[title]
        if tabBarButton.waitForExistence(timeout: 5) {
            tabBarButton.tap()
            return
        }
        // iPad regular-width uses a sidebar List instead of a tab bar.
        app.buttons[title].firstMatch.tap()
    }

    // MARK: (a) Touchpad — 20 short right-swipes + a tap

    @MainActor
    func testA_Touchpad() throws {
        let app = launchAndWaitForConnected()
        selectTab("Touchpad", in: app)

        let surface = app.otherElements["touchpad.surface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 10), "touchpad.surface not found. \(debugDetail(app))")

        for _ in 0..<20 {
            surface.swipeRight()
        }
        surface.tap()

        XCTAssertTrue(app.state == .runningForeground, "App left foreground after touchpad gestures. \(debugDetail(app))")
    }

    // MARK: (b) Keyboard — live-mode typing

    @MainActor
    func testB_Keyboard() throws {
        let app = launchAndWaitForConnected()
        selectTab("Keyboard", in: app)

        // Best-effort tap: the live-input host is a hidden 1x1pt capture view that already
        // becomes first responder automatically once this tab appears (KeyboardViewModel
        // .onAppear()), so a failed/absent tap here is not itself a test failure.
        let liveInput = app.otherElements["keyboard.liveInput"]
        if liveInput.waitForExistence(timeout: 2), liveInput.isHittable {
            liveInput.tap()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        app.typeText("airmouse ok\n")

        XCTAssertTrue(app.state == .runningForeground, "App left foreground after keyboard typing. \(debugDetail(app))")
    }

    // MARK: (c) Remote — Media segment play/pause + volume up

    @MainActor
    func testC_Remote() throws {
        let app = launchAndWaitForConnected()
        selectTab("Remote", in: app)

        let mediaSegment = app.segmentedControls.buttons["Media"]
        XCTAssertTrue(mediaSegment.waitForExistence(timeout: 5), "Media segment not found. \(debugDetail(app))")
        mediaSegment.tap()

        let playPause = app.buttons["remote.playPause"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 5), "remote.playPause not found. \(debugDetail(app))")
        playPause.tap()

        let volumeUp = app.buttons["remote.volumeUp"]
        XCTAssertTrue(volumeUp.waitForExistence(timeout: 5), "remote.volumeUp not found. \(debugDetail(app))")
        volumeUp.tap()

        XCTAssertTrue(app.state == .runningForeground, "App left foreground after remote taps. \(debugDetail(app))")
    }

    // MARK: (d) Macros — shows either macro buttons or the empty state, never an error

    @MainActor
    func testD_Macros() throws {
        let app = launchAndWaitForConnected()
        selectTab("Macros", in: app)

        // Give the (possibly network-backed) macro list a moment to settle.
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        let visibleTexts = app.staticTexts.allElementsBoundByIndex.prefix(40).map(\.label).joined(separator: " | ")
        let hasEmptyState = app.staticTexts["No macros yet"].exists
        let hasMacroButtons = app.buttons.matching(NSPredicate(format: "identifier != 'Settings'")).count > 0
        let hasErrorAlert = app.alerts.count > 0

        XCTAssertFalse(hasErrorAlert, "Macros tab showed an error alert. Visible texts: \(visibleTexts)")
        XCTAssertTrue(hasEmptyState || hasMacroButtons, "Macros tab showed neither macro buttons nor the empty state. Visible texts: \(visibleTexts)")
    }

    // MARK: (e) Background / foreground

    @MainActor
    func testE_BackgroundForeground() throws {
        let app = launchAndWaitForConnected()

        XCUIDevice.shared.press(.home)
        RunLoop.current.run(until: Date().addingTimeInterval(5))
        app.activate()

        XCTAssertTrue(waitForConnected(app, timeout: 10), "Did not return to connected within 10s of foregrounding. \(debugDetail(app))")
    }

    // MARK: (f) Settings — toggle natural scrolling (scroll-direction picker), no crash

    @MainActor
    func testF_Settings() throws {
        let app = launchAndWaitForConnected()

        let gear = app.buttons["Settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5), "Settings gear not found. \(debugDetail(app))")
        gear.tap()

        let scrollDirectionRow = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Scroll direction'")).firstMatch
        let rowExists = scrollDirectionRow.waitForExistence(timeout: 5)
        XCTAssertTrue(rowExists, "Scroll direction row not found. \(debugDetail(app))")
        if rowExists {
            scrollDirectionRow.tap()

            let inverted = app.buttons["Inverted"]
            if inverted.waitForExistence(timeout: 5) {
                inverted.tap()
            }
            // Back to the Settings root.
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        let done = app.buttons["Done"]
        if done.waitForExistence(timeout: 5) {
            done.tap()
        }

        XCTAssertTrue(app.state == .runningForeground, "App left foreground / crashed during Settings interaction. \(debugDetail(app))")
    }
}
