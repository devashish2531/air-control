// Tests/AirMouseViewModelTests.swift
// Feature-level behavior: clutch haptics, click-area tap-vs-hold-to-drag (spec §4.1.5's "hold ≥
// 250 ms = drag while held"), scroll strip phases, and recenter.
import AirMouseFilters
import AirMouseProtocol
import Foundation
import Testing
@testable import Air_Mouse

@MainActor
@Suite struct AirMouseViewModelTests {
    @Test func holdModeClutchFiresEngageThenReleaseHaptics() async {
        let haptics = FakeHapticsService()
        let viewModel = makeAirMouseViewModel(clutchMode: .hold, haptics: haptics)

        viewModel.clutchPressBegan()
        #expect(haptics.firedEvents == [.clutchEngage])

        viewModel.clutchPressEnded()
        #expect(haptics.firedEvents == [.clutchEngage, .clutchRelease])
    }

    @Test func toggleModeClutchFiresEngageOnFirstTapAndReleaseOnSecond() async {
        let haptics = FakeHapticsService()
        let viewModel = makeAirMouseViewModel(clutchMode: .toggle, haptics: haptics)

        viewModel.clutchPressBegan() // no-op in toggle mode
        #expect(haptics.firedEvents.isEmpty)

        viewModel.clutchPressEnded() // tap 1: engage
        #expect(haptics.firedEvents == [.clutchEngage])
        #expect(await waitUntil { viewModel.engine.state == .armed })

        viewModel.clutchPressEnded() // tap 2: release
        #expect(haptics.firedEvents == [.clutchEngage, .clutchRelease])
    }

    @Test func quickPrimaryPressSendsASingleTapClick() async {
        let controlSink = FakeControlMessageSink()
        let viewModel = makeAirMouseViewModel(controlSink: controlSink)

        viewModel.primaryPressBegan()
        try? await Task.sleep(nanoseconds: 30_000_000) // well under the 250 ms hold threshold
        viewModel.primaryPressEnded()

        #expect(await controlSink.waitForClickCount(1))
        #expect(controlSink.clicks == [Click(button: .left, action: .tap, count: 1, modifiers: [])])
        #expect(viewModel.isPrimaryClickDragging == false)
    }

    @Test func longPrimaryPressEntersDragAndSendsDownThenUp() async {
        let controlSink = FakeControlMessageSink()
        let viewModel = makeAirMouseViewModel(controlSink: controlSink)

        viewModel.primaryPressBegan()
        #expect(await waitUntil(timeout: 1) { viewModel.isPrimaryClickDragging })
        #expect(await controlSink.waitForClickCount(1))

        viewModel.primaryPressEnded()
        #expect(await controlSink.waitForClickCount(2))
        #expect(controlSink.clicks == [
            Click(button: .left, action: .down, count: 1, modifiers: []),
            Click(button: .left, action: .up, count: 1, modifiers: []),
        ])
        #expect(viewModel.isPrimaryClickDragging == false)
    }

    @Test func secondaryClickUsesRightButton() async {
        let controlSink = FakeControlMessageSink()
        let viewModel = makeAirMouseViewModel(controlSink: controlSink)

        viewModel.secondaryPressBegan()
        try? await Task.sleep(nanoseconds: 30_000_000)
        viewModel.secondaryPressEnded()

        #expect(await controlSink.waitForClickCount(1))
        #expect(controlSink.clicks == [Click(button: .right, action: .tap, count: 1, modifiers: [])])
    }

    @Test func scrollDragReportsBeganEndedPhasesAndPerStepDeltas() async {
        let controlSink = FakeControlMessageSink()
        let motionSink = FakeMotionEnqueuer()
        let viewModel = makeAirMouseViewModel(controlSink: controlSink, motionSink: motionSink)

        viewModel.scrollChanged(translationY: 10)
        viewModel.scrollChanged(translationY: 25)
        viewModel.scrollEnded(velocityY: 100)

        #expect(controlSink.scrollPhases.first?.phase == .began)
        #expect(controlSink.scrollPhases.last?.phase == .ended)
        #expect(controlSink.scrollPhases.last?.vy == 100)

        try? await Task.sleep(nanoseconds: 30_000_000) // scroll deltas go through the async motion sink
        let deltas = await motionSink.scrollDeltas
        #expect(deltas.map(\.y) == [10, 15]) // cumulative translation -> per-step deltas
        #expect(viewModel.isScrolling == false)
    }

    @Test func recenterButtonTriggersEngineRecenterAndHaptic() {
        let haptics = FakeHapticsService()
        let viewModel = makeAirMouseViewModel(haptics: haptics)

        viewModel.recenterButtonTapped()
        #expect(viewModel.engine.recenterCallCount == 1)
        #expect(haptics.firedEvents == [.modifierToggle])
    }
}
