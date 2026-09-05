// Support/Logging.swift
// os.Logger categories for the iOS app. Subsystem per arch §8 ("Cross-cutting concerns" → Logging):
// `com.airmouse.app`. Never log keys, secrets, typed text, or full fingerprints (spec §7).

import os

/// Namespaced `Logger` instances, one per architectural area, so log filtering in Console.app
/// can isolate a subsystem quickly (`subsystem:com.airmouse.app category:net`).
public enum Log {
    private static let subsystem = "com.airmouse.app"

    /// App lifecycle, scene phase, DI wiring.
    public static let app = Logger(subsystem: subsystem, category: "app")
    /// Networking / connection manager (owned by the Connection agent; the shell only logs wiring events).
    public static let net = Logger(subsystem: subsystem, category: "net")
    /// Motion / gyro publishing (owned by the Motion agent; shell logs lifecycle only).
    public static let motion = Logger(subsystem: subsystem, category: "motion")
    /// Onboarding flow.
    public static let onboarding = Logger(subsystem: subsystem, category: "onboarding")
    /// Settings persistence and effective-settings layering.
    public static let settings = Logger(subsystem: subsystem, category: "settings")
    /// Keychain and document store persistence.
    public static let store = Logger(subsystem: subsystem, category: "store")
    /// Haptics and feedback.
    public static let haptics = Logger(subsystem: subsystem, category: "haptics")
    /// Diagnostics HUD and log export.
    public static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")
    /// Deep-link and pairing routing (shell-side forwarding only).
    public static let deepLink = Logger(subsystem: subsystem, category: "deeplink")
    /// User-facing error presentation.
    public static let errors = Logger(subsystem: subsystem, category: "errors")
}
