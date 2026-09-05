// Tests/ModifierLatchStateTests.swift
// `ModifierLatchState` is the pure latch/lock state machine behind the Keyboard modifier row
// (spec §4.4.4). These tests drive it with an injected `ContinuousClock.Instant` so the 300 ms
// double-tap window (spec §11.3 `doubleTapInterval`) is exercised deterministically.

import Testing
import AirMouseProtocol
@testable import Air_Mouse

@Suite struct ModifierLatchStateTests {
    @Test func tapFromOffLatches() {
        var state = ModifierLatchState()
        let t0 = ContinuousClock.now
        let result = state.tap(.command, at: t0)
        #expect(result == .latched)
        #expect(state.state(for: .command) == .latched)
    }

    @Test func latchIsConsumedAfterOneKey() {
        var state = ModifierLatchState()
        let t0 = ContinuousClock.now
        state.tap(.shift, at: t0)
        #expect(state.state(for: .shift) == .latched)
        state.consumeLatchesAfterKey()
        #expect(state.state(for: .shift) == .off)
    }

    @Test func doubleTapWithinWindowLocks() {
        var state = ModifierLatchState()
        let t0 = ContinuousClock.now
        state.tap(.option, at: t0)
        let result = state.tap(.option, at: t0.advanced(by: .milliseconds(150)))
        #expect(result == .locked)
        #expect(state.state(for: .option) == .locked)
    }

    @Test func lockPersistsAcrossConsumedKeys() {
        var state = ModifierLatchState()
        let t0 = ContinuousClock.now
        state.tap(.control, at: t0)
        state.tap(.control, at: t0.advanced(by: .milliseconds(100)))
        #expect(state.state(for: .control) == .locked)

        state.consumeLatchesAfterKey()
        #expect(state.state(for: .control) == .locked)
        state.consumeLatchesAfterKey()
        #expect(state.state(for: .control) == .locked)
    }

    @Test func slowSecondTapCancelsLatchInsteadOfLocking() {
        var state = ModifierLatchState()
        let t0 = ContinuousClock.now
        state.tap(.command, at: t0)
        let result = state.tap(.command, at: t0.advanced(by: .milliseconds(500)))
        #expect(result == .off)
        #expect(state.state(for: .command) == .off)
    }

    @Test func tapWhileLockedClearsToOff() {
        var state = ModifierLatchState()
        let t0 = ContinuousClock.now
        state.tap(.shift, at: t0)
        state.tap(.shift, at: t0.advanced(by: .milliseconds(50))) // -> locked
        #expect(state.state(for: .shift) == .locked)

        let result = state.tap(.shift, at: t0.advanced(by: .seconds(2)))
        #expect(result == .off)
        #expect(state.state(for: .shift) == .off)
    }

    @Test func clearResetsEveryKey() {
        var state = ModifierLatchState()
        let t0 = ContinuousClock.now
        state.tap(.command, at: t0)
        state.tap(.shift, at: t0)
        state.tap(.shift, at: t0.advanced(by: .milliseconds(10))) // locked
        #expect(state.state(for: .command) == .latched)
        #expect(state.state(for: .shift) == .locked)

        state.clear()
        for key in ModifierKey.allCases {
            #expect(state.state(for: key) == .off)
        }
    }

    @Test func activeFlagsUnionsLatchedAndLockedKeys() {
        var state = ModifierLatchState()
        let t0 = ContinuousClock.now
        state.tap(.command, at: t0)
        state.tap(.shift, at: t0)
        state.tap(.shift, at: t0.advanced(by: .milliseconds(10))) // locked

        let flags = state.activeFlags
        #expect(flags.contains(.command))
        #expect(flags.contains(.shift))
        #expect(!flags.contains(.option))
    }

    @Test func modifierKeysAreIndependent() {
        var state = ModifierLatchState()
        let t0 = ContinuousClock.now
        state.tap(.command, at: t0)
        state.tap(.option, at: t0.advanced(by: .seconds(5))) // well outside .command's window
        #expect(state.state(for: .command) == .latched)
        #expect(state.state(for: .option) == .latched)

        state.consumeLatchesAfterKey()
        #expect(state.state(for: .command) == .off)
        #expect(state.state(for: .option) == .off)
    }
}
