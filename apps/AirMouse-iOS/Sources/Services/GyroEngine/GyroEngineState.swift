// Services/GyroEngine/GyroEngineState.swift
// The engine's user-visible state machine. Not in spec by this exact name, but it is the natural
// decomposition of spec §4.3's behaviors the UI must render: the first-use/"Recalibrate now" hold
// (§4.3.7), the clutch gate (§4.3.6), and whether motion is actually flowing right now (so the
// status card can distinguish "armed, holding still" from "moving").
public enum GyroEngineState: Sendable, Equatable {
    /// Not calibrating, clutch disengaged. The default state, and where a `stop()`ped engine sits.
    case idle
    /// Hold-still calibration in progress (initial first-use card, or "Recalibrate now").
    case calibrating
    /// Clutch engaged, but the last processed sample produced no delta (still/dead-zoned).
    case armed
    /// Clutch engaged and pointer deltas are actively being produced.
    case moving
}
