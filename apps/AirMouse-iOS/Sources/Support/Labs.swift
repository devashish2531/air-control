// Support/Labs.swift
// Feature flags per arch §8 ("Feature flags / Labs"): a small @Observable wrapper over `am.labs.*`
// UserDefaults keys (arch §6.2). Always default off; surfaced in Settings › Advanced (spec §4.1.9)
// and Settings › Pointer (Prediction, spec §4.1.9 table).

import Foundation
import Observation

/// `UserDefaults` keys for Labs flags (arch §6.2).
public enum LabsKey {
    public static let prediction = "am.labs.prediction"
    public static let latencyHUD = "am.labs.latencyHUD"
    public static let tcpMotionOnly = "am.labs.tcpMotionOnly"
}

/// Runtime feature flags. Compile-time flags are avoided per arch §8; these are the only
/// user-toggleable behavior switches in the shell. Backed by `UserDefaults.standard` directly
/// (not routed through `UserSettings`/`DocumentStore`) because Labs flags are explicitly
/// described as always-off, developer-facing toggles distinct from the settings snapshot.
@MainActor
@Observable
public final class Labs {
    private let defaults: UserDefaults

    /// Client-side pointer prediction (spec §5.3.2, ≤ 16 ms). The host independently honours
    /// its own Labs toggle; this only sets the client's `flags.predicted` bit.
    public var prediction: Bool {
        didSet { defaults.set(prediction, forKey: LabsKey.prediction) }
    }

    /// Shows the Diagnostics latency HUD overlay (arch §8.2) on top of feature screens.
    public var latencyHUD: Bool {
        didSet { defaults.set(latencyHUD, forKey: LabsKey.latencyHUD) }
    }

    /// Forces the TCP motion fallback path for debugging (spec §3.5.8).
    public var tcpMotionOnly: Bool {
        didSet { defaults.set(tcpMotionOnly, forKey: LabsKey.tcpMotionOnly) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.prediction = defaults.object(forKey: LabsKey.prediction) as? Bool ?? false
        self.latencyHUD = defaults.object(forKey: LabsKey.latencyHUD) as? Bool ?? false
        self.tcpMotionOnly = defaults.object(forKey: LabsKey.tcpMotionOnly) as? Bool ?? false
    }
}
