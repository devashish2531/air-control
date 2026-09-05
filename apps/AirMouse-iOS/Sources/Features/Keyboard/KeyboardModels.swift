// Features/Keyboard/KeyboardModels.swift
// Value types the Keyboard screen's views bind to: the extended key bar's key identities and the
// shortcut palette's chords (spec §4.1.6, §4.4.5 FR-KB-008).

import Foundation
import AirMouseProtocol

/// One button on the extended key bar (spec §4.1.6: "Esc, Tab, ⇥, ↑↓←→, ⌫, ⌦, Home, End, PgUp,
/// PgDn, F1–F12"). `Tab` and `⇥` name the same key, so there is only one `.tab` case.
public enum ExtendedKey: Sendable, Hashable, Identifiable, CaseIterable {
    case escape, tab, deleteBackward, deleteForward, `return`
    case arrowLeft, arrowUp, arrowDown, arrowRight
    case home, end, pageUp, pageDown
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12

    public var id: Self { self }

    public var virtualKey: UInt16 {
        switch self {
        case .escape: VirtualKey.kVK_Escape
        case .tab: VirtualKey.kVK_Tab
        case .deleteBackward: VirtualKey.kVK_Delete
        case .deleteForward: VirtualKey.kVK_ForwardDelete
        case .return: VirtualKey.kVK_Return
        case .arrowLeft: VirtualKey.kVK_LeftArrow
        case .arrowUp: VirtualKey.kVK_UpArrow
        case .arrowDown: VirtualKey.kVK_DownArrow
        case .arrowRight: VirtualKey.kVK_RightArrow
        case .home: VirtualKey.kVK_Home
        case .end: VirtualKey.kVK_End
        case .pageUp: VirtualKey.kVK_PageUp
        case .pageDown: VirtualKey.kVK_PageDown
        case .f1: VirtualKey.kVK_F1
        case .f2: VirtualKey.kVK_F2
        case .f3: VirtualKey.kVK_F3
        case .f4: VirtualKey.kVK_F4
        case .f5: VirtualKey.kVK_F5
        case .f6: VirtualKey.kVK_F6
        case .f7: VirtualKey.kVK_F7
        case .f8: VirtualKey.kVK_F8
        case .f9: VirtualKey.kVK_F9
        case .f10: VirtualKey.kVK_F10
        case .f11: VirtualKey.kVK_F11
        case .f12: VirtualKey.kVK_F12
        }
    }

    /// Whether this key auto-repeats while held (spec §4.4.3: "Arrow/Delete/Space/Page keys on
    /// the bar send `key{down}` on touch-down and `key{up}` on release so the host auto-repeats").
    public var autoRepeatsOnHold: Bool {
        switch self {
        case .arrowLeft, .arrowUp, .arrowDown, .arrowRight, .deleteBackward, .deleteForward, .pageUp, .pageDown:
            true
        default:
            false
        }
    }

    public var symbolName: String {
        switch self {
        case .escape: "escape"
        case .tab: "arrow.right.to.line"
        case .deleteBackward: "delete.left"
        case .deleteForward: "delete.right"
        case .return: "return"
        case .arrowLeft: "arrow.left"
        case .arrowUp: "arrow.up"
        case .arrowDown: "arrow.down"
        case .arrowRight: "arrow.right"
        case .home: "arrow.up.to.line.compact"
        case .end: "arrow.down.to.line.compact"
        case .pageUp: "arrow.up.doc"
        case .pageDown: "arrow.down.doc"
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12: "f.cursive"
        }
    }

    /// Short glyph shown on the button face — F-keys show their number; everything else is
    /// icon-only (`symbolName`) with this as the accessibility label fallback.
    public var label: String {
        switch self {
        case .escape: String(localized: "Esc", comment: "Keyboard extended key bar: Escape key button label")
        case .tab: String(localized: "Tab", comment: "Keyboard extended key bar: Tab key button label")
        case .deleteBackward: String(localized: "Delete", comment: "Keyboard extended key bar: Delete/backspace key accessibility label")
        case .deleteForward: String(localized: "Forward Delete", comment: "Keyboard extended key bar: Forward Delete key accessibility label")
        case .return: String(localized: "Return", comment: "Keyboard extended key bar: Return key button label")
        case .arrowLeft: String(localized: "Left arrow", comment: "Keyboard extended key bar: accessibility label")
        case .arrowUp: String(localized: "Up arrow", comment: "Keyboard extended key bar: accessibility label")
        case .arrowDown: String(localized: "Down arrow", comment: "Keyboard extended key bar: accessibility label")
        case .arrowRight: String(localized: "Right arrow", comment: "Keyboard extended key bar: accessibility label")
        case .home: String(localized: "Home", comment: "Keyboard extended key bar: Home key button label")
        case .end: String(localized: "End", comment: "Keyboard extended key bar: End key button label")
        case .pageUp: String(localized: "Page Up", comment: "Keyboard extended key bar: Page Up key accessibility label")
        case .pageDown: String(localized: "Page Down", comment: "Keyboard extended key bar: Page Down key accessibility label")
        case .f1: "F1"
        case .f2: "F2"
        case .f3: "F3"
        case .f4: "F4"
        case .f5: "F5"
        case .f6: "F6"
        case .f7: "F7"
        case .f8: "F8"
        case .f9: "F9"
        case .f10: "F10"
        case .f11: "F11"
        case .f12: "F12"
        }
    }

    /// Whether the button face shows the text label (Esc/Tab/Return read better as text) rather
    /// than `symbolName`'s SF Symbol.
    public var prefersTextGlyph: Bool {
        switch self {
        case .escape, .tab, .return: true
        default: false
        }
    }

    public static let editingCluster: [ExtendedKey] = [.escape, .tab, .return, .deleteBackward, .deleteForward]
    public static let arrowCluster: [ExtendedKey] = [.arrowLeft, .arrowUp, .arrowDown, .arrowRight]
    public static let navCluster: [ExtendedKey] = [.home, .end, .pageUp, .pageDown]
    public static let functionRow: [ExtendedKey] = [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]
}

/// fn-toggled media-glyph substitute for an F-row key (spec §4.4.4: "fn is a client-side toggle
/// that switches the F-row between `key{F#}` and `mediaKey`"). Only the F-keys with a real Mac
/// media-key equivalent (mirroring Apple's own F-row legends) have an entry here; the rest
/// (Mission Control/Launchpad/Dictation/Do Not Disturb have no `MediaKey` case) keep sending their
/// plain F-key code even while the row is showing media glyphs.
public enum FRowMediaGlyph {
    public static let mapping: [ExtendedKey: (key: MediaKey, symbolName: String, label: String)] = [
        .f1: (.brightnessDown, "sun.min", String(localized: "Brightness down", comment: "Keyboard extended key bar: fn-toggled media glyph label")),
        .f2: (.brightnessUp, "sun.max", String(localized: "Brightness up", comment: "Keyboard extended key bar: fn-toggled media glyph label")),
        .f7: (.rewind, "backward.fill", String(localized: "Rewind", comment: "Keyboard extended key bar: fn-toggled media glyph label")),
        .f8: (.playPause, "playpause.fill", String(localized: "Play/Pause", comment: "Keyboard extended key bar: fn-toggled media glyph label")),
        .f9: (.fastForward, "forward.fill", String(localized: "Fast forward", comment: "Keyboard extended key bar: fn-toggled media glyph label")),
        .f10: (.mute, "speaker.slash.fill", String(localized: "Mute", comment: "Keyboard extended key bar: fn-toggled media glyph label")),
        .f11: (.volumeDown, "speaker.wave.1.fill", String(localized: "Volume down", comment: "Keyboard extended key bar: fn-toggled media glyph label")),
        .f12: (.volumeUp, "speaker.wave.3.fill", String(localized: "Volume up", comment: "Keyboard extended key bar: fn-toggled media glyph label")),
    ]
}

/// Shortcut-palette default chords (spec §4.4.5 FR-KB-008: "⌘Space, ⌘Tab, ⌘Q, ⌘W, ⌘Z, ⌘⇧Z, ⌘C,
/// ⌘V, ⌘⇧4, ⌘⌥Esc, ⌃⌘Q — each one `key{tap}`; user-editable"). `KeyboardViewModel.shortcutRow`
/// defaults to this agent's narrower assignment list (⌘Space, ⌘Tab, ⌘C/V, ⌘Z, ⌘Q, screenshot);
/// every other case here is still available to add back via the shortcut editor sheet.
public enum ShortcutChord: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case commandSpace
    case commandTab
    case commandQ
    case commandW
    case commandZ
    case commandShiftZ
    case commandC
    case commandV
    case screenshot // ⌘⇧4
    case commandOptionEscape
    case controlCommandQ

    public var id: String { rawValue }

    public var virtualKey: UInt16 {
        switch self {
        case .commandSpace: VirtualKey.kVK_Space
        case .commandTab: VirtualKey.kVK_Tab
        case .commandQ, .controlCommandQ: VirtualKey.kVK_ANSI_Q
        case .commandW: VirtualKey.kVK_ANSI_W
        case .commandZ, .commandShiftZ: VirtualKey.kVK_ANSI_Z
        case .commandC: VirtualKey.kVK_ANSI_C
        case .commandV: VirtualKey.kVK_ANSI_V
        case .screenshot: VirtualKey.kVK_ANSI_4
        case .commandOptionEscape: VirtualKey.kVK_Escape
        }
    }

    public var modifiers: KeyModifiers {
        switch self {
        case .commandSpace, .commandTab, .commandQ, .commandW, .commandZ, .commandC, .commandV: [.command]
        case .commandShiftZ, .screenshot: [.command, .shift]
        case .commandOptionEscape: [.command, .option]
        case .controlCommandQ: [.control, .command]
        }
    }

    /// Symbolic on-button label (⌘/⌥/⌃/⇧ glyphs read the same in every locale).
    public var label: String {
        switch self {
        case .commandSpace: "⌘Space"
        case .commandTab: "⌘Tab"
        case .commandQ: "⌘Q"
        case .commandW: "⌘W"
        case .commandZ: "⌘Z"
        case .commandShiftZ: "⌘⇧Z"
        case .commandC: "⌘C"
        case .commandV: "⌘V"
        case .screenshot: "⌘⇧4"
        case .commandOptionEscape: "⌘⌥Esc"
        case .controlCommandQ: "⌃⌘Q"
        }
    }

    /// Spoken accessibility label (spec §4.8: every key has an accessibility label).
    public var accessibilityLabel: String {
        switch self {
        case .commandSpace: String(localized: "Command Space", comment: "Shortcut palette: accessibility label")
        case .commandTab: String(localized: "Command Tab", comment: "Shortcut palette: accessibility label")
        case .commandQ: String(localized: "Command Q, Quit", comment: "Shortcut palette: accessibility label")
        case .commandW: String(localized: "Command W, Close Window", comment: "Shortcut palette: accessibility label")
        case .commandZ: String(localized: "Command Z, Undo", comment: "Shortcut palette: accessibility label")
        case .commandShiftZ: String(localized: "Command Shift Z, Redo", comment: "Shortcut palette: accessibility label")
        case .commandC: String(localized: "Command C, Copy", comment: "Shortcut palette: accessibility label")
        case .commandV: String(localized: "Command V, Paste", comment: "Shortcut palette: accessibility label")
        case .screenshot: String(localized: "Command Shift 4, Screenshot", comment: "Shortcut palette: accessibility label")
        case .commandOptionEscape: String(localized: "Command Option Escape, Force Quit", comment: "Shortcut palette: accessibility label")
        case .controlCommandQ: String(localized: "Control Command Q, Lock Screen", comment: "Shortcut palette: accessibility label")
        }
    }

    /// This agent's assignment default row (a narrower subset of FR-KB-008's full default list).
    public static let defaultRow: [ShortcutChord] = [.commandSpace, .commandTab, .commandC, .commandV, .commandZ, .commandQ, .screenshot]
}
