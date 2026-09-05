// Features/AirMouse/ClampedComparable.swift
// Tiny clamp helper used when applying the Gyro settings sliders (spec §4.1.9's sensitivity /
// smoothing / dead-zone ranges) to `UserSettings`.
extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
