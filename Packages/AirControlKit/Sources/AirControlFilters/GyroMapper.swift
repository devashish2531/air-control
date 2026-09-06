import Foundation
import simd

/// Whether the clutch (the control that gates gyro motion datagrams, spec §4.3.6) is held down or
/// toggled on/off.
public enum ClutchMode: Sendable, Equatable {
    case hold
    case toggle
}

/// Gyro engine: angular rate (rad/s, device frame) + gravity vector -> pointer delta in points
/// (spec §4.3.2–§4.3.6).
///
/// `update(rotationRate:gravity:timestamp:)` implements, per sample:
/// 1. gravity-aware yaw/pitch decomposition (§4.3.2),
/// 2. stillness-driven bias subtraction (§4.3.5),
/// 3. dead zone (§4.3.3),
/// 4. integration of the dead-zoned rate into an angle, then a One-Euro filter applied to that
///    *integrated angle* — not the rate — per §4.3.4, whose consecutive-sample difference is the
///    output delta,
/// 5. gain (§4.3.2).
///
/// Motion is only produced while the clutch is engaged (`engage()`/`disengage()`/
/// `toggleEngagement()`); `recenter()` flushes filter/integrator history for a clean restart
/// (spec §4.3.6's double-tap/shake recenter).
public struct GyroMapper: Sendable {
    /// Reference gain: `G₀ = 1920 px / (40°·π/180) ≈ 2750 px/rad` (spec §4.3.2).
    public static let referenceGain: Double = 2750

    /// Dead zone, degrees/s (spec §4.3.3 default; allowed range 0...3 per §11.3).
    public var deadZoneDegPerSec: Double
    /// Reference gain in px/rad (spec `G₀`).
    public var gainG0PxPerRad: Double
    /// Sensitivity slider, 1...10 -> gain multiplier 0.5x...2.5x (spec §4.3.2).
    public var sensitivity: Double
    public var orientation: Orientation
    public var clutchMode: ClutchMode

    public private(set) var isEngaged: Bool = false

    private var bias = BiasEstimator()
    private var stillness = StillnessDetector()
    private var stillnessDuration: TimeInterval = 0

    private var yawFilter: OneEuroFilter
    private var pitchFilter: OneEuroFilter
    private var thetaYaw: Double = 0
    private var thetaPitch: Double = 0
    private var lastFilteredYaw: Double = 0
    private var lastFilteredPitch: Double = 0
    private var lastTimestamp: TimeInterval?
    private var currentAxis: SIMD3<Double>

    /// - Parameter minCutoffSlider: One-Euro `minCutoff` slider, 0...10 (0 bypasses filtering,
    ///   1 = 10 Hz, 10 = 0.5 Hz geometric — spec §4.3.4).
    public init(
        deadZoneDegPerSec: Double = 0.5,
        gainG0PxPerRad: Double = GyroMapper.referenceGain,
        sensitivity: Double = 5,
        minCutoffSlider: Double = 5,
        orientation: Orientation = .portrait,
        clutchMode: ClutchMode = .hold
    ) {
        self.deadZoneDegPerSec = deadZoneDegPerSec
        self.gainG0PxPerRad = gainG0PxPerRad
        self.sensitivity = sensitivity
        self.orientation = orientation
        self.clutchMode = clutchMode
        self.currentAxis = orientation.deviceAxis ?? SIMD3(1, 0, 0)

        let minCutoff = GyroMapper.minCutoff(forSlider: minCutoffSlider)
        // beta = 1.0 Hz per (°/s); the integrated angle (and hence its derivative dx̂) is tracked in
        // radians here, so convert: 1 Hz per °/s == (180/π) Hz per rad/s.
        let beta = 1.0 * (180.0 / Double.pi)
        self.yawFilter = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: 1.0)
        self.pitchFilter = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: 1.0)
    }

    /// spec §4.3.4: minCutoff geometric from 10 Hz (slider 1) to 0.5 Hz (slider 10); slider 0
    /// bypasses the filter entirely (modeled here as an effectively infinite cutoff, i.e. alpha ~ 1).
    public static func minCutoff(forSlider slider: Double) -> Double {
        guard slider > 0 else { return .infinity }
        let clamped = Swift.min(Swift.max(slider, 1), 10)
        let t = (clamped - 1) / 9
        return 10.0 * pow(0.5 / 10.0, t)
    }

    /// spec §4.3.2: `G = G₀ · 0.5 · 5^((s−1)/9)`, i.e. 0.5x...2.5x of `gainG0PxPerRad` over
    /// sensitivity 1...10.
    public var gain: Double {
        let s = Swift.min(Swift.max(sensitivity, 1), 10)
        return gainG0PxPerRad * 0.5 * pow(5.0, (s - 1) / 9)
    }

    /// Applies a new interface orientation. `.suspended` (and any future orientation without an
    /// axis) is a no-op — the previously active axis is kept.
    public mutating func setOrientation(_ o: Orientation) {
        guard let axis = o.deviceAxis else { return }
        orientation = o
        currentAxis = axis
    }

    public mutating func engage() {
        isEngaged = true
        lastTimestamp = nil // avoid a huge dt across the disengaged gap
    }

    public mutating func disengage() {
        isEngaged = false
    }

    public mutating func toggleEngagement() {
        isEngaged.toggle()
        if isEngaged { lastTimestamp = nil }
    }

    /// spec §4.3.6 recenter: flush integrator/filter history for a clean restart. Does not touch the
    /// learned drift bias, which is independent of any absolute angle.
    public mutating func recenter() {
        thetaYaw = 0
        thetaPitch = 0
        lastFilteredYaw = 0
        lastFilteredPitch = 0
        yawFilter.reset()
        pitchFilter.reset()
        lastTimestamp = nil
    }

    /// spec §4.3.3: `f₁(ω) = 0 if |ω| < dz else sign(ω)·(|ω| − dz)` — continuous at the boundary.
    private static func deadZone(_ omega: Double, degreesPerSecond dz: Double) -> Double {
        let dzRad = dz * Double.pi / 180
        let magnitude = Swift.abs(omega)
        guard magnitude > dzRad else { return 0 }
        return (omega < 0 ? -1.0 : 1.0) * (magnitude - dzRad)
    }

    /// Maps one CoreMotion-style sample to a pointer delta in points, or `nil` when the clutch is
    /// disengaged (spec: "motion datagrams are sent only while the clutch is engaged") or this is
    /// the bootstrap sample after `engage()`/`recenter()` (which seeds state instead of emitting).
    ///
    /// - Parameters:
    ///   - rotationRate: bias-corrected angular rate, rad/s, device frame.
    ///   - gravity: gravity vector, device frame (need not be pre-normalized).
    ///   - userAcceleration: optional linear acceleration (g) for the auto-freeze stillness check
    ///     (spec §4.3.5). The base `update(rotationRate:gravity:timestamp:)` call this module was
    ///     specified with omits it (auto-freeze needs CoreMotion's `userAcceleration`, which is an
    ///     iOS-layer concern); passing it here opts into the full auto-freeze behavior.
    ///   - timestamp: seconds, monotonic for this mapper instance.
    public mutating func update(
        rotationRate w: SIMD3<Double>,
        gravity: SIMD3<Double>,
        userAcceleration: SIMD3<Double>? = nil,
        timestamp: TimeInterval
    ) -> Delta? {
        guard isEngaged else { return nil }

        let g = simd_length(gravity) > 1e-9 ? simd_normalize(gravity) : SIMD3<Double>(0, -1, 0)
        let ex = currentAxis
        let rawYaw = -simd_dot(w, g)
        let hxRaw = ex - simd_dot(ex, g) * g
        let hx = simd_length(hxRaw) > 1e-9 ? simd_normalize(hxRaw) : ex
        let rawPitch = -simd_dot(w, hx)

        let biasedYaw = rawYaw - bias.bias.x
        let biasedPitch = rawPitch - bias.bias.y

        let dzYaw = Self.deadZone(biasedYaw, degreesPerSecond: deadZoneDegPerSec)
        let dzPitch = Self.deadZone(biasedPitch, degreesPerSecond: deadZoneDegPerSec)

        guard let last = lastTimestamp else {
            // Bootstrap sample: seed the filters/integrators, emit no delta (spec's steady-state
            // formula needs a previous filtered angle to difference against).
            lastTimestamp = timestamp
            thetaYaw = 0
            thetaPitch = 0
            lastFilteredYaw = yawFilter.filter(0, t: timestamp)
            lastFilteredPitch = pitchFilter.filter(0, t: timestamp)
            return nil
        }

        let rawDt = timestamp - last
        let dt = Swift.min(Swift.max(rawDt, 0.005), 0.020) // spec: Δt clamped 5...20 ms
        lastTimestamp = timestamp

        // Stillness-driven drift bias EMA (spec §4.3.5): only while both dead-zoned axes are zero.
        if dzYaw == 0 && dzPitch == 0 {
            stillnessDuration += Swift.max(rawDt, 0)
        } else {
            stillnessDuration = 0
        }
        if stillnessDuration >= 0.300 {
            bias.update(rawYaw: rawYaw, rawPitch: rawPitch)
        }

        if let ua = userAcceleration {
            let magnitude = Double(simd_length(ua))
            let quiet = stillness.update(magnitude: magnitude, timestamp: timestamp)
            if quiet && dzYaw == 0 && dzPitch == 0 {
                return Delta.zero
            }
        }

        thetaYaw += dzYaw * dt
        thetaPitch += dzPitch * dt

        let filteredYaw = yawFilter.filter(thetaYaw, t: timestamp)
        let filteredPitch = pitchFilter.filter(thetaPitch, t: timestamp)
        let deltaYaw = filteredYaw - lastFilteredYaw
        let deltaPitch = filteredPitch - lastFilteredPitch
        lastFilteredYaw = filteredYaw
        lastFilteredPitch = filteredPitch

        return Delta(dx: gain * deltaYaw, dy: gain * deltaPitch)
    }
}
