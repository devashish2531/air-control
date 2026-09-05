// Support/Accessibility.swift
// Helpers for spec §4.8.1 accessibility rules: Dynamic Type, VoiceOver labels, minimum tap
// targets, and "colour never sole signal". Individual feature screens are responsible for
// applying these on every interactive element; these helpers exist so the rules are easy to
// apply consistently rather than re-derived per screen.

import SwiftUI

public enum A11y {
    /// Minimum tap target side length (44 pt), used throughout the spec for buttons, click
    /// areas, and the clutch (spec §4.1.4, §4.1.5, HIG minimum).
    public static let minimumTapTarget: CGFloat = 44

    /// Dynamic Type ceiling the app supports without clipping (spec §4.8.1.3): accessibility XXXL.
    public static let maximumDynamicTypeSize: DynamicTypeSize = .accessibility5
}

public extension View {
    /// Ensures a tappable control never falls below the HIG/spec minimum hit target, regardless
    /// of its visual content size.
    func minimumTapTarget() -> some View {
        frame(minWidth: A11y.minimumTapTarget, minHeight: A11y.minimumTapTarget)
    }

    /// Clamps Dynamic Type to the range the app has verified does not clip (spec §4.8.1.3).
    /// `minimumScaleFactor` is intentionally never used on labels per that rule.
    func airMouseDynamicTypeRange() -> some View {
        dynamicTypeSize(...A11y.maximumDynamicTypeSize)
    }

    /// Applies an accessibility label and optional hint in one call, and marks the element a
    /// button — the common case for icon-only controls (spec §4.8.1.1).
    func accessibleButton(label: LocalizedStringKey, hint: LocalizedStringKey? = nil) -> some View {
        var view = AnyView(self)
        view = AnyView(view.accessibilityLabel(label))
        if let hint {
            view = AnyView(view.accessibilityHint(hint))
        }
        return view.accessibilityAddTraits(.isButton)
    }

    /// Marks a control as "selected"/latched for modifier-key style toggles, in addition to
    /// whatever visual latch styling the view applies — colour is never the sole signal
    /// (spec §4.8.1.5).
    func accessibleLatched(_ isLatched: Bool) -> some View {
        accessibilityAddTraits(isLatched ? .isSelected : [])
    }
}

/// Convenience check for Reduce Motion, per spec §4.8.1.4: decorative animation should be
/// disabled (trail fade becomes instant, tutorial animations become static images) when true.
@MainActor
public enum ReduceMotion {
    public static var isEnabled: Bool {
        UIAccessibility.isReduceMotionEnabled
    }
}
