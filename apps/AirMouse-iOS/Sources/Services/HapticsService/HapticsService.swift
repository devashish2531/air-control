// Services/HapticsService/HapticsService.swift
// Haptic + sound feedback per spec §4.6 and accessibility rule §4.8.1.9 (individually togglable,
// visual-pulse fallback on hardware without a Taptic Engine). Generators are `prepare()`d on
// touch-down by callers (spec §4.6); this service exposes `prepare(_:)` for that purpose.

import UIKit
import CoreHaptics
import Observation

/// Every feedback event named in spec §4.6's table.
public enum HapticEvent: Sendable, CaseIterable {
    /// Tap recognised (left click).
    case tapClick
    /// Right click / two-finger tap / long-press threshold.
    case secondaryClick
    /// On-screen click button / gyro click area pressed down.
    case buttonDown
    /// On-screen click button / gyro click area released.
    case buttonUp
    /// Drag-lock engaged.
    case dragLockEngage
    /// Drag-lock released.
    case dragLockRelease
    /// Clutch engaged.
    case clutchEngage
    /// Clutch released.
    case clutchRelease
    /// Modifier latch or lock toggled.
    case modifierToggle
    /// Macro invoked, or a successful `macroResult`.
    case macroSuccess
    /// A failed `macroResult`.
    case macroFailure
    /// Pairing completed successfully.
    case pairingSuccess
    /// Pairing failed.
    case pairingFailure
    /// Presenter countdown reached 5:00 or 1:00 remaining.
    case countdownWarning
}

/// Feedback delivery, decided per-event by hardware capability and settings — never both a
/// haptic AND its sound fallback are required to be the same kind: a click also plays a sound
/// when sound feedback is on.
@MainActor
public protocol HapticsService: AnyObject {
    /// Whether haptic feedback is currently enabled (Feedback › Haptics, spec §4.1.9).
    var isHapticsEnabled: Bool { get set }
    /// Whether feedback sounds are currently enabled (Feedback › Sounds, spec §4.1.9).
    var isSoundEnabled: Bool { get set }

    /// Pre-warms the generator(s) involved in `event`. Call on touch-down (spec §4.6).
    func prepare(_ event: HapticEvent)
    /// Fires the feedback for `event`, respecting the current settings and hardware support.
    func fire(_ event: HapticEvent)
}

/// UIKit-backed implementation using `UIImpactFeedbackGenerator` / `UISelectionFeedbackGenerator`
/// / `UINotificationFeedbackGenerator` per spec §4.6's table. On hardware without a Taptic Engine
/// (`CHHapticEngine.capabilitiesForHardware().supportsHaptics == false`, most iPads), a 120 ms
/// visual pulse is posted instead (spec §4.6, §4.8.1.9) via `visualPulsePublisher`.
@MainActor
@Observable
public final class UIKitHapticsService: HapticsService {
    public var isHapticsEnabled: Bool
    public var isSoundEnabled: Bool

    /// Set by the view layer that renders the 120 ms visual pulse fallback; bumped on every
    /// `fire(_:)` call when haptics are enabled but hardware support is absent.
    public private(set) var lastVisualPulse: HapticEvent?

    private let supportsHaptics: Bool
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    public init(isHapticsEnabled: Bool = true, isSoundEnabled: Bool = true, supportsHaptics: Bool? = nil) {
        self.isHapticsEnabled = isHapticsEnabled
        self.isSoundEnabled = isSoundEnabled
        if let supportsHaptics {
            self.supportsHaptics = supportsHaptics
        } else {
            self.supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        }
    }

    public func prepare(_ event: HapticEvent) {
        guard isHapticsEnabled, supportsHaptics else { return }
        switch event {
        case .tapClick, .buttonUp, .clutchRelease:
            lightImpact.prepare()
        case .secondaryClick:
            mediumImpact.prepare()
        case .buttonDown, .clutchEngage:
            rigidImpact.prepare()
        case .dragLockEngage, .dragLockRelease, .modifierToggle:
            selection.prepare()
        case .macroSuccess, .macroFailure, .pairingSuccess, .pairingFailure:
            notification.prepare()
        case .countdownWarning:
            notification.prepare()
        }
    }

    public func fire(_ event: HapticEvent) {
        guard isHapticsEnabled else { return }
        guard supportsHaptics else {
            lastVisualPulse = event
            return
        }
        switch event {
        case .tapClick, .buttonUp, .clutchRelease:
            lightImpact.impactOccurred()
        case .secondaryClick:
            mediumImpact.impactOccurred()
        case .buttonDown, .clutchEngage:
            rigidImpact.impactOccurred()
        case .dragLockEngage, .dragLockRelease, .modifierToggle:
            selection.selectionChanged()
        case .macroSuccess, .pairingSuccess:
            notification.notificationOccurred(.success)
        case .macroFailure, .pairingFailure:
            notification.notificationOccurred(.error)
        case .countdownWarning:
            notification.notificationOccurred(.warning)
        }
    }
}
