// Services/GyroEngine/SystemClock.swift
// Real-time `Clock` (`Packages/AirMouseKit/Sources/AirMouseFilters/Clock.swift`) for `GyroEngine`'s
// wall-clock bookkeeping (double-tap window, click motion-suppression, shake debounce — spec
// §4.3.6). Backed by `ProcessInfo.systemUptime`, the same clock domain as `CMDeviceMotion.timestamp`
// (both monotonic, unaffected by system clock changes), so engine-level timestamps and
// CoreMotion-sourced sample timestamps are directly comparable.
import AirMouseFilters
import Foundation

public struct SystemClock: Clock {
    public init() {}
    public func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}
