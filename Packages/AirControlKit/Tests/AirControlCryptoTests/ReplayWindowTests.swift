import Testing
@testable import AirControlCrypto

@Suite struct ReplayWindowTests {
    @Test func inOrderAllAccepted() {
        var window = ReplayWindow()
        for counter: UInt64 in 0..<10 {
            #expect(window.accept(counter) == .accepted)
        }
        #expect(window.highest == 9)
    }

    @Test func duplicateIsRejectedAsReplay() {
        var window = ReplayWindow()
        #expect(window.accept(0) == .accepted)
        #expect(window.accept(1) == .accepted)
        #expect(window.accept(1) == .rejectedReplay)
    }

    @Test func outOfOrderWithinWindowIsAccepted() {
        var window = ReplayWindow()
        #expect(window.accept(10) == .accepted)
        #expect(window.accept(8) == .accepted) // arrived late, but within window
        #expect(window.accept(8) == .rejectedReplay) // now a duplicate
        #expect(window.accept(9) == .accepted)
    }

    @Test func farFutureJumpResetsWindow() {
        var window = ReplayWindow()
        #expect(window.accept(0) == .accepted)
        #expect(window.accept(1) == .accepted)
        #expect(window.accept(1_000_000) == .accepted)
        #expect(window.highest == 1_000_000)
        // Anything from the old, pre-jump range is now unrepresentable and must be "too old".
        #expect(window.accept(1) == .rejectedTooOld)
    }

    @Test func exactlyAtWindowBoundaryIsTooOld() {
        var window = ReplayWindow()
        #expect(window.accept(200) == .accepted)
        // 200 - 136 == 64 == ReplayWindow.size -> too old (spec §6.4: "136 is exactly 64 behind 200").
        #expect(window.accept(136) == .rejectedTooOld)
    }

    @Test func oneInsideWindowBoundaryIsAccepted() {
        var window = ReplayWindow()
        #expect(window.accept(200) == .accepted)
        // 200 - 137 == 63 < 64 -> still inside the window.
        #expect(window.accept(137) == .accepted)
    }

    @Test func wraparoundNearUInt64Max() {
        var window = ReplayWindow(highest: UInt64.max - 5, bitmap: 0b1)
        #expect(window.accept(UInt64.max - 4) == .accepted)
        #expect(window.accept(UInt64.max) == .accepted)
        #expect(window.highest == UInt64.max)
        // A duplicate of the new maximum is rejected.
        #expect(window.accept(UInt64.max) == .rejectedReplay)
        // Nothing can exceed UInt64.max, so any subsequent counter is <= highest; verify the "too
        // old" branch doesn't trap when computing highest - counter with huge highest values.
        #expect(window.accept(0) == .rejectedTooOld)
    }

    @Test func startingFromZeroStateAcceptsFirstZeroCounter() {
        // The very first datagram in a session has counter == 0 (spec §3.5.1); the window's initial
        // state (highest: 0, bitmap: 0) must not treat that as a duplicate of an implicit "already
        // seen 0" state.
        var window = ReplayWindow()
        #expect(window.accept(0) == .accepted)
    }

    @Test func specVectorSequenceMatchesAlgorithm() throws {
        let vector = try VectorFile.load("replay_window_vector")
        let sequence = (vector["sequence"] as! [Int]).map { UInt64($0) }
        let expected = (vector["decisions"] as! [String]).map { decodeDecision($0) }

        var window = ReplayWindow()
        var actual: [ReplayWindow.Decision] = []
        for counter in sequence {
            actual.append(window.accept(counter))
        }
        #expect(actual == expected)
    }

    private func decodeDecision(_ name: String) -> ReplayWindow.Decision {
        switch name {
        case "accepted": return .accepted
        case "rejectedReplay": return .rejectedReplay
        case "rejectedTooOld": return .rejectedTooOld
        default: fatalError("unknown decision \(name)")
        }
    }

    // MARK: - Separate application-level "stale to apply" (8-behind) helper

    @Test func staleToApplyThresholdIsEight() {
        #expect(ReplayWindow.isStaleToApply(counter: 92, highestApplied: 100) == false) // 8 behind: not stale
        #expect(ReplayWindow.isStaleToApply(counter: 91, highestApplied: 100) == true) // 9 behind: stale
        #expect(ReplayWindow.isStaleToApply(counter: 100, highestApplied: 100) == false) // current: not stale
        #expect(ReplayWindow.isStaleToApply(counter: 105, highestApplied: 100) == false) // ahead: not stale
    }

    @Test func staleToApplyIsIndependentOfTheSixtyFourWideWindow() {
        // A counter can be accepted by the 64-wide replay window yet still be stale-to-apply under
        // the separate 8-wide rule (spec §3.5.4).
        #expect(ReplayWindow.isStaleToApply(counter: 50, highestApplied: 100) == true)
    }
}
