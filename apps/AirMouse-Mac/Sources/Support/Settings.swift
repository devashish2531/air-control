// arch §6.2 "UserDefaults keys" (macOS rows). Backs the Preferences window (Features/Preferences).
//
// Deviation: a few Preferences fields the assignment asked for have no key in arch §6.2's table
// (pointer acceleration/sensitivity defaults, a device display name, a pairing-window timeout, and an
// interval for the non-Sparkle `UpdateService` stub). Those are added below as new `am.helper.*` keys with
// their own doc comment; every key that *is* in arch §6.2 uses exactly that key name and default.
import Foundation
import Observation

/// `@Observable` wrapper over the helper's `UserDefaults` keys (arch §6.2). One instance should be shared
/// (via `AppEnvironment`) so every window observes the same live values. All access happens on the main
/// actor since this drives SwiftUI.
@MainActor
@Observable
public final class HostSettings {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func bool(_ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? value
    }

    private func int(_ key: String, default value: Int) -> Int {
        defaults.object(forKey: key) as? Int ?? value
    }

    private func string(_ key: String, default value: String) -> String {
        defaults.string(forKey: key) ?? value
    }

    // MARK: General

    public var setupCompleted: Bool {
        get { bool(Keys.setupCompleted, default: false) }
        set { defaults.set(newValue, forKey: Keys.setupCompleted) }
    }

    public var launchAtLogin: Bool {
        get { bool(Keys.launchAtLogin, default: true) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    /// Off by default: a second `LaunchAgent` watchdog is only installed when the user opts in (spec §5.7.1).
    public var relaunchWatchdog: Bool {
        get { bool(Keys.relaunchWatchdog, default: false) }
        set { defaults.set(newValue, forKey: Keys.relaunchWatchdog) }
    }

    /// Not in arch §6.2's table; the name shown to phones during pairing/connection. Defaults to the
    /// Mac's local host name.
    public var deviceDisplayName: String {
        get { string(Keys.deviceDisplayName, default: Host.current().localizedName ?? "Mac") }
        set { defaults.set(newValue, forKey: Keys.deviceDisplayName) }
    }

    // MARK: Pointer

    /// Not in arch §6.2; a host-side default later consumed by the acceleration/filters pipeline
    /// (owned by another agent). Range 0...1, 1.0 = system default curve.
    public var pointerAccelerationDefault: Double {
        get { defaults.object(forKey: Keys.pointerAccelerationDefault) as? Double ?? 1.0 }
        set { defaults.set(newValue, forKey: Keys.pointerAccelerationDefault) }
    }

    /// Not in arch §6.2; see `pointerAccelerationDefault`.
    public var pointerSensitivityDefault: Double {
        get { defaults.object(forKey: Keys.pointerSensitivityDefault) as? Double ?? 1.0 }
        set { defaults.set(newValue, forKey: Keys.pointerSensitivityDefault) }
    }

    public enum NaturalScrollOverride: String, CaseIterable, Sendable {
        case system, natural, inverted
    }

    public var naturalScrollOverride: NaturalScrollOverride {
        get { NaturalScrollOverride(rawValue: string(Keys.naturalScrollOverride, default: "system")) ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Keys.naturalScrollOverride) }
    }

    // MARK: Security

    public var allowScriptsGlobal: Bool {
        get { bool(Keys.allowScriptsGlobal, default: false) }
        set { defaults.set(newValue, forKey: Keys.allowScriptsGlobal) }
    }

    public var requireConfirmationAll: Bool {
        get { bool(Keys.requireConfirmationAll, default: false) }
        set { defaults.set(newValue, forKey: Keys.requireConfirmationAll) }
    }

    /// Not in arch §6.2; spec §5.1.3 fixes the pairing window at 60 s but the assignment asked for a
    /// Preferences control, so this is exposed as an editable default with the spec value as the default.
    public var pairingWindowTimeoutSeconds: Int {
        get { int(Keys.pairingWindowTimeoutSeconds, default: 60) }
        set { defaults.set(newValue, forKey: Keys.pairingWindowTimeoutSeconds) }
    }

    // MARK: Updates

    /// Opt-in, default off (spec §5.7.2 / FR-MB-007).
    public var updateCheckOptIn: Bool {
        get { bool(Keys.updateCheckOptIn, default: false) }
        set { defaults.set(newValue, forKey: Keys.updateCheckOptIn) }
    }

    /// Not in arch §6.2 (Sparkle's own interval is a fixed 86400 s per spec §5.7.2, not user-configurable);
    /// this drives the interim `GitHubReleasesUpdateChecker` stub instead (`// TODO(M8): Sparkle`).
    public var updateCheckIntervalHours: Int {
        get { int(Keys.updateCheckIntervalHours, default: 24) }
        set { defaults.set(newValue, forKey: Keys.updateCheckIntervalHours) }
    }

    // MARK: Advanced

    public var logLevel: LogLevel {
        get { LogLevel(rawValue: string(Keys.logLevel, default: LogLevel.default.rawValue)) ?? .default }
        set { defaults.set(newValue.rawValue, forKey: Keys.logLevel) }
    }

    public var tcpPort: Int {
        get { int(Keys.tcpPort, default: 47800) }
        set { defaults.set(newValue, forKey: Keys.tcpPort) }
    }

    public var udpPort: Int {
        get { int(Keys.udpPort, default: 47800) }
        set { defaults.set(newValue, forKey: Keys.udpPort) }
    }

    /// Labs item; hidden behind Settings › Advanced, always default off (arch §8).
    public var labsPrediction: Bool {
        get { bool(Keys.labsPrediction, default: false) }
        set { defaults.set(newValue, forKey: Keys.labsPrediction) }
    }

    private enum Keys {
        static let setupCompleted = "am.helper.setupCompleted"
        static let launchAtLogin = "am.helper.launchAtLogin"
        static let relaunchWatchdog = "am.helper.relaunchWatchdog"
        static let deviceDisplayName = "am.helper.deviceDisplayName"
        static let pointerAccelerationDefault = "am.helper.pointerAccelerationDefault"
        static let pointerSensitivityDefault = "am.helper.pointerSensitivityDefault"
        static let naturalScrollOverride = "am.helper.naturalScrollOverride"
        static let allowScriptsGlobal = "am.helper.allowScriptsGlobal"
        static let requireConfirmationAll = "am.helper.requireConfirmationAll"
        static let pairingWindowTimeoutSeconds = "am.helper.pairingWindowTimeoutSeconds"
        static let updateCheckOptIn = "am.helper.updateCheckOptIn"
        static let updateCheckIntervalHours = "am.helper.updateCheckIntervalHours"
        static let logLevel = "am.helper.logLevel"
        static let tcpPort = "am.helper.tcpPort"
        static let udpPort = "am.helper.udpPort"
        static let labsPrediction = "am.helper.labs.prediction"
    }
}
