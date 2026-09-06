// Support/AppTab.swift
// The five root tabs (spec §4.1) as a shared identifier — used by `RootTabView` for navigation
// and by `UserSettings.defaultTab` (spec AM-ST-05 / §4.1.9 Appearance "Default tab").

import Foundation

public enum AppTab: String, Codable, CaseIterable, Sendable, Identifiable {
    case touchpad
    case airPointer
    case keyboard
    case remote
    case macros

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .touchpad: return String(localized: "Touchpad", comment: "Root tab title")
        case .airPointer: return String(localized: "Air Pointer", comment: "Root tab title")
        case .keyboard: return String(localized: "Keyboard", comment: "Root tab title")
        case .remote: return String(localized: "Remote", comment: "Root tab title")
        case .macros: return String(localized: "Macros", comment: "Root tab title")
        }
    }

    public var systemImage: String {
        switch self {
        case .touchpad: return "hand.point.up.left"
        case .airPointer: return "gyroscope"
        case .keyboard: return "keyboard"
        case .remote: return "play.rectangle"
        case .macros: return "square.grid.2x2"
        }
    }
}
