// Tests/RemoteModelTests.swift
// Button→sink command mapping table for the Remote tab (spec §4.1.7), plus presenter-profile
// detection and the media launcher row's `showOnMediaPage`/cap-at-8 filtering. A `FakeRemoteCommandSink`
// records every call so each button's mapping can be asserted directly, independent of any real
// Connection agent implementation.

import Testing
import Foundation
import AirControlProtocol
@testable import Air_Control

/// Plain structs (not tuples) so recorded-call arrays get automatic `Equatable`/array-`==`
/// conformance for direct assertions.
struct SentShortcut: Equatable {
    let virtualKey: UInt16
    let modifiers: KeyModifiers
}

struct MacroInvokeCall: Equatable {
    let id: UUID
    let confirmed: Bool
}

@MainActor
private final class FakeRemoteCommandSink: RemoteCommandSink {
    private(set) var sentMediaKeys: [MediaKey] = []
    private(set) var sentShortcuts: [SentShortcut] = []
    private(set) var invokeMacroCalls: [MacroInvokeCall] = []
    var invokeMacroOutcome: MacroInvokeOutcome = MacroInvokeOutcome(code: .ok)
    var macroListResult: [Macro] = []

    var frontmostAppName: String?
    var scriptsAllowedOnHost: Bool = true

    func sendMediaKey(_ key: MediaKey) {
        sentMediaKeys.append(key)
    }

    func sendShortcut(virtualKey: UInt16, modifiers: KeyModifiers) {
        sentShortcuts.append(SentShortcut(virtualKey: virtualKey, modifiers: modifiers))
    }

    func invokeMacro(id: UUID, confirmed: Bool) async throws -> MacroInvokeOutcome {
        invokeMacroCalls.append(MacroInvokeCall(id: id, confirmed: confirmed))
        return invokeMacroOutcome
    }

    func requestMacroList() async throws -> [Macro] {
        macroListResult
    }
}

private func makeMacro(
    name: String = "Test Macro",
    icon: String = "star",
    action: MacroAction = .launchApp(bundleID: "com.example.app", activateIfRunning: true),
    page: Int = 0,
    order: Int = 0,
    showOnMediaPage: Bool = false
) -> Macro {
    Macro(name: name, icon: icon, action: action, page: page, order: order, showOnMediaPage: showOnMediaPage)
}

@MainActor
@Suite struct RemoteModelTests {
    // MARK: - Presenter button → sink mapping

    @Test func previousAndNextSlideSendArrowShortcuts() {
        let sink = FakeRemoteCommandSink()
        let model = RemoteModel(sink: sink)

        model.previousSlide()
        model.nextSlide()

        #expect(sink.sentShortcuts.map(\.virtualKey) == [VirtualKey.kVK_LeftArrow, VirtualKey.kVK_RightArrow])
        #expect(sink.sentShortcuts.allSatisfy { $0.modifiers.isEmpty })
    }

    @Test func blankScreenSendsBKey() {
        let sink = FakeRemoteCommandSink()
        let model = RemoteModel(sink: sink)

        model.blankScreen()

        #expect(sink.sentShortcuts.first?.virtualKey == VirtualKey.kVK_ANSI_B)
    }

    @Test func exitPresentationSendsEscape() {
        let sink = FakeRemoteCommandSink()
        let model = RemoteModel(sink: sink)

        model.exitPresentation()

        #expect(sink.sentShortcuts.first?.virtualKey == VirtualKey.kVK_Escape)
    }

    @Test func lockScreenSendsControlCommandQ() throws {
        let sink = FakeRemoteCommandSink()
        let model = RemoteModel(sink: sink)

        model.lockScreen()

        let shortcut = try #require(sink.sentShortcuts.first)
        #expect(shortcut.virtualKey == VirtualKey.kVK_ANSI_Q)
        #expect(shortcut.modifiers == [.control, .command])
    }

    @Test func startPresentationIsProfileDependent() throws {
        let sink = FakeRemoteCommandSink()
        let model = RemoteModel(sink: sink)

        sink.frontmostAppName = "Keynote"
        model.startPresentation()
        var shortcut = try #require(sink.sentShortcuts.last)
        #expect(shortcut.virtualKey == VirtualKey.kVK_ANSI_P)
        #expect(shortcut.modifiers == [.option, .command])

        sink.frontmostAppName = "Microsoft PowerPoint"
        model.startPresentation()
        shortcut = try #require(sink.sentShortcuts.last)
        #expect(shortcut.virtualKey == VirtualKey.kVK_Return)
        #expect(shortcut.modifiers == [.shift, .command])

        sink.frontmostAppName = "Finder"
        model.startPresentation()
        shortcut = try #require(sink.sentShortcuts.last)
        #expect(shortcut.virtualKey == VirtualKey.kVK_F5)
        #expect(shortcut.modifiers.isEmpty)

        sink.frontmostAppName = nil
        model.startPresentation()
        shortcut = try #require(sink.sentShortcuts.last)
        #expect(shortcut.virtualKey == VirtualKey.kVK_F5)
    }

    @Test func pointerSpotlightPostsSwitchToTouchpadNotification() async {
        let sink = FakeRemoteCommandSink()
        let model = RemoteModel(sink: sink)

        await confirmation { received in
            let observer = NotificationCenter.default.addObserver(forName: RemoteModel.switchToTouchpadNotification, object: nil, queue: nil) { _ in
                received()
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            model.togglePointerSpotlight()
        }
    }

    // MARK: - Media button → sink mapping

    @Test func mediaTransportButtonsMapToMediaKeys() {
        let sink = FakeRemoteCommandSink()
        let model = RemoteModel(sink: sink)

        model.mediaPlayPause()
        model.mediaPrevious()
        model.mediaNext()
        model.mute()

        #expect(sink.sentMediaKeys == [.playPause, .previous, .next, .mute])
    }

    @Test func seekUsesArrowsGenericallyAndJLInBrowsers() {
        let sink = FakeRemoteCommandSink()
        let model = RemoteModel(sink: sink)

        model.seekBackward()
        model.seekForward()
        #expect(sink.sentShortcuts.map(\.virtualKey) == [VirtualKey.kVK_LeftArrow, VirtualKey.kVK_RightArrow])

        sink.frontmostAppName = "Safari"
        model.seekBackward()
        model.seekForward()
        #expect(sink.sentShortcuts.suffix(2).map(\.virtualKey) == [VirtualKey.kVK_ANSI_J, VirtualKey.kVK_ANSI_L])
    }

    @Test func volumeAndBrightnessHoldFiresImmediatelyAndStopsOnRelease() {
        let sink = FakeRemoteCommandSink()
        let model = RemoteModel(sink: sink)

        model.startVolumeUp()
        #expect(sink.sentMediaKeys == [.volumeUp])
        model.stopVolumeRepeat()

        model.startBrightnessDown()
        #expect(sink.sentMediaKeys == [.volumeUp, .brightnessDown])
        model.stopBrightnessRepeat()
    }

    // MARK: - Presenter profile detection

    @Test func presenterProfileDetection() {
        #expect(PresenterProfile.detect(fromFrontmostAppName: "Keynote") == .keynote)
        #expect(PresenterProfile.detect(fromFrontmostAppName: "Microsoft PowerPoint") == .powerPoint)
        #expect(PresenterProfile.detect(fromFrontmostAppName: "TextEdit") == .generic)
        #expect(PresenterProfile.detect(fromFrontmostAppName: nil) == .generic)
    }

    // MARK: - Media launcher row (spec §4.1.7: up to 8 showOnMediaPage macros)

    @Test func mediaLauncherRowFiltersShowOnMediaPageAndCapsAtEight() async {
        let sink = FakeRemoteCommandSink()
        var macros: [Macro] = []
        for i in 0..<10 {
            macros.append(makeMacro(name: "Media \(i)", page: 0, order: i, showOnMediaPage: true))
        }
        macros.append(makeMacro(name: "Hidden", page: 1, order: 0, showOnMediaPage: false))
        sink.macroListResult = macros

        let model = RemoteModel(sink: sink)
        await model.loadMediaLauncherButtons()

        #expect(model.mediaLauncherButtons.count == 8)
        #expect(model.mediaLauncherButtons.map(\.macro.name) == (0..<8).map { "Media \($0)" })
    }

    @Test func invokeLauncherMacroCallsSinkWithoutConfirmation() async {
        let sink = FakeRemoteCommandSink()
        let model = RemoteModel(sink: sink)
        let macro = makeMacro(showOnMediaPage: true)

        await model.invokeLauncherMacro(macro)

        #expect(sink.invokeMacroCalls == [MacroInvokeCall(id: macro.id, confirmed: false)])
    }
}
