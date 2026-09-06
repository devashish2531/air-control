// Support/SystemClock.swift
// Real-time `AirControlFilters.Clock` for `ClientSession` (spec §3.4.6/§8.2 RTT bookkeeping) — mirrors
// `apps/AirControl-iOS/Sources/Services/GyroEngine/SystemClock.swift`'s pattern (same `Clock` protocol,
// same `ProcessInfo.systemUptime` backing), reimplemented here because `aircontrol-cli` cannot depend on
// the iOS app target.
import AirControlFilters
import Foundation

struct SystemClock: Clock {
    func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}
