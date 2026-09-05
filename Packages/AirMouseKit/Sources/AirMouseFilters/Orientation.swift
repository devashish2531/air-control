import simd

/// Interface orientation as it affects the gyro engine's device-horizontal axis (spec §4.3.2):
/// "device X axis `ex = (1,0,0)` re-oriented per interface orientation: portrait: `ex`;
/// landscapeLeft: `ey`; landscapeRight: `−ey`; upside-down: `−ex`; suspended when 'Lock orientation'
/// is on".
public enum Orientation: Sendable, Equatable {
    case portrait
    case landscapeLeft
    case landscapeRight
    case upsideDown
    /// "Lock orientation" is on: interface-orientation tracking is suspended, so `GyroMapper` keeps
    /// whichever axis was last active instead of recomputing one.
    case suspended

    /// The device X axis for this orientation, or `nil` for `.suspended` (meaning: don't change it).
    public var deviceAxis: SIMD3<Double>? {
        switch self {
        case .portrait: return SIMD3(1, 0, 0)
        case .landscapeLeft: return SIMD3(0, 1, 0)
        case .landscapeRight: return SIMD3(0, -1, 0)
        case .upsideDown: return SIMD3(-1, 0, 0)
        case .suspended: return nil
        }
    }
}
