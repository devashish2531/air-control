// Support/SystemClock.swift
// Real-time `AirMouseFilters.Clock` for `ClientSession` (spec §3.4.6/§8.2 RTT bookkeeping) — mirrors
// `apps/AirMouse-iOS/Sources/Services/GyroEngine/SystemClock.swift`'s pattern (same `Clock` protocol,
// same `ProcessInfo.systemUptime` backing), reimplemented here because `airmouse-cli` cannot depend on
// the iOS app target.
import AirMouseFilters
import Foundation

struct SystemClock: Clock {
    func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}
