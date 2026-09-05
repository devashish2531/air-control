import XCTest

/// On-device pairing regression. Run with the pairing URL from the Mac helper (`--print-pair-url`):
///   AIRMOUSE_PAIR_URL='airmouse://pair?...' xcodebuild test ... -only-testing:AirMouseUITests/PairingUITests
/// The test runner forwards the variable to the app, whose DEBUG launch hook routes it through PairingRouting.
final class PairingUITests: XCTestCase {
    @MainActor
    func testPairFromLaunchURLReachesConnected() throws {
        guard let url = ProcessInfo.processInfo.environment["AIRMOUSE_PAIR_URL"], !url.isEmpty else {
            throw XCTSkip("AIRMOUSE_PAIR_URL not set; skipping on-device pairing test")
        }
        let app = XCUIApplication()
        app.launchEnvironment["AIRMOUSE_PAIR_URL"] = url
        // Accept the Local Network / camera system alerts if they appear.
        addUIInterruptionMonitor(withDescription: "System permission alert") { alert in
            for label in ["Allow", "OK", "Allow While Using App"] {
                let button = alert.buttons[label]
                if button.exists { button.tap(); return true }
            }
            return false
        }
        app.launch()
        app.tap() // trigger any pending interruption monitor

        let connected = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Connected' AND NOT label CONTAINS[c] 'Not connected'")).firstMatch
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline, !connected.exists {
            app.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        let diagnostics = app.staticTexts.allElementsBoundByIndex.prefix(40).map(\.label).joined(separator: " | ")
        XCTAssertTrue(connected.exists, "Did not reach Connected within 45 s. Visible texts: \(diagnostics)")
    }
}
