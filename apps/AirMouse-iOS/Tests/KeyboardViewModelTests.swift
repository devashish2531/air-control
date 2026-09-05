// Tests/KeyboardViewModelTests.swift
// Commit-mode buffering (spec §4.4.2 "Commit"): the buffer accumulates until Send, chunks on
// grapheme-cluster boundaries at 4 KB, and clears after sending. Uses a fake `KeyboardEventSink`
// so no real transport is involved.

import Testing
import Foundation
import AirMouseProtocol
@testable import Air_Mouse

@MainActor
private final class FakeKeyboardEventSink: KeyboardEventSink {
    private(set) var sentText: [String] = []
    private(set) var sentKeys: [(virtualKey: UInt16, char: String?, modifiers: KeyModifiers, isDown: Bool)] = []
    private(set) var sentMediaKeys: [MediaKey] = []

    func sendKey(virtualKey: UInt16, char: String?, modifiers: KeyModifiers, isDown: Bool) {
        sentKeys.append((virtualKey, char, modifiers, isDown))
    }

    func sendText(_ text: String) {
        sentText.append(text)
    }

    func sendMediaKey(_ key: MediaKey) {
        sentMediaKeys.append(key)
    }
}

@MainActor
@Suite struct KeyboardViewModelTests {
    private func makeViewModel() -> (KeyboardViewModel, FakeKeyboardEventSink) {
        let sink = FakeKeyboardEventSink()
        let viewModel = KeyboardViewModel(sink: sink, haptics: UIKitHapticsService(supportsHaptics: false))
        return (viewModel, sink)
    }

    @Test func shortTextIsSentAsOneChunkAndBufferClears() {
        let (viewModel, sink) = makeViewModel()
        viewModel.mode = .commit
        viewModel.commitText = "Hello, Mac!"
        viewModel.sendCommit()

        #expect(sink.sentText == ["Hello, Mac!"])
        #expect(viewModel.commitText == "")
    }

    @Test func emptyBufferSendsNothing() {
        let (viewModel, sink) = makeViewModel()
        viewModel.mode = .commit
        viewModel.commitText = ""
        viewModel.sendCommit()
        #expect(sink.sentText.isEmpty)
    }

    @Test func longTextIsChunkedOnGraphemeBoundariesAt4KB() {
        let (viewModel, sink) = makeViewModel()
        viewModel.mode = .commit
        // 5000 ASCII characters (1 byte each) → should split into two chunks (4096 + 904).
        viewModel.commitText = String(repeating: "a", count: 5000)
        viewModel.sendCommit()

        #expect(sink.sentText.count == 2)
        #expect(sink.sentText[0].utf8.count == 4096)
        #expect(sink.sentText[1].utf8.count == 904)
        #expect(sink.sentText.joined().count == 5000)
        #expect(viewModel.commitText == "")
    }

    @Test func chunkingNeverSplitsAGraphemeCluster() {
        let (viewModel, sink) = makeViewModel()
        viewModel.mode = .commit
        // Flag emoji is a multi-scalar grapheme cluster several bytes wide; repeat it enough to
        // cross the 4 KB boundary and confirm no chunk ends mid-cluster.
        let flag = "🇺🇸" // 8 UTF-8 bytes as a single Character
        viewModel.commitText = String(repeating: flag, count: 1000)
        viewModel.sendCommit()

        for chunk in sink.sentText {
            #expect(chunk.utf8.count <= 4096)
            // Every chunk boundary lands on a whole flag — a mid-cluster split would leave stray
            // scalars that don't recompose into whole "🇺🇸" characters, changing this count.
            #expect(chunk.filter { $0 == Character(flag) }.count * flag.utf8.count == chunk.utf8.count)
        }
        #expect(sink.sentText.joined() == String(repeating: flag, count: 1000))
    }

    @Test func returnSendsGatesCommitReturn() {
        // `returnSends` is backed by `UserDefaults.standard` in the production type; this test
        // only exercises the in-memory toggle + `handleCommitReturn` gating, not persistence
        // (which would require touching the shared standard defaults).
        let (viewModel, sink) = makeViewModel()
        viewModel.mode = .commit
        viewModel.commitText = "queued"

        viewModel.returnSends = false
        #expect(viewModel.handleCommitReturn() == false)
        #expect(sink.sentText.isEmpty)
        #expect(viewModel.commitText == "queued")

        viewModel.returnSends = true
        #expect(viewModel.handleCommitReturn() == true)
        #expect(sink.sentText == ["queued"])
        #expect(viewModel.commitText == "")
    }

    @Test func switchingToCommitModeClearsAnyPriorBuffer() {
        let (viewModel, _) = makeViewModel()
        viewModel.mode = .commit
        viewModel.commitText = "leftover"
        viewModel.mode = .live
        viewModel.mode = .commit
        #expect(viewModel.commitText == "")
    }
}
