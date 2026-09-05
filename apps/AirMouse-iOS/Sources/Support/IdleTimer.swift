// Support/IdleTimer.swift
// Keep-screen-awake behavior (spec §4.6 "Screen kept awake while Connected and foregrounded";
// AM-ST-03). `UIApplication.isIdleTimerDisabled` is process-global, so this wraps it behind a
// small ref-counted API keyed by reason, and the app-level "keep screen awake" setting.

import UIKit
import Observation

/// Ref-counts requests to disable the idle timer so independent features (e.g. Touchpad while
/// `Connected`, a future full-screen presenter mode) don't clobber each other's intent when they
/// enable/disable independently and out of order.
@MainActor
@Observable
public final class IdleTimer {
    private var reasons: Set<String> = []
    /// Global opt-out — mirrors the "Keep screen awake" Feedback setting (spec §4.1.9). When
    /// false, the idle timer is always left enabled regardless of active reasons.
    public var isEnabledBySettings: Bool = true {
        didSet { apply() }
    }

    public init() {}

    /// Requests the idle timer stay disabled for `reason` (e.g. `"connected"`). Call
    /// `release(_:)` with the same reason when the condition no longer holds.
    public func acquire(_ reason: String) {
        reasons.insert(reason)
        apply()
    }

    public func release(_ reason: String) {
        reasons.remove(reason)
        apply()
    }

    private func apply() {
        UIApplication.shared.isIdleTimerDisabled = isEnabledBySettings && !reasons.isEmpty
    }
}
