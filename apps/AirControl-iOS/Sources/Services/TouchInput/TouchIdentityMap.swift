// Services/TouchInput/TouchIdentityMap.swift
// Stable per-touch identity, mapping a live `UITouch`'s `ObjectIdentifier` to the small `Int`
// `AirControlFilters.TouchID` expects (spec §4.2.1: "id via ObjectIdentifier map"). Kept as its own
// value type (rather than inline dictionaries in `TouchpadUIView`) so the id-assignment/release
// bookkeeping is unit-testable without a real `UITouch` — any `AnyObject` (e.g. a plain `NSObject`
// in tests) has an `ObjectIdentifier`.
public struct TouchIdentityMap: Sendable {
    private var ids: [ObjectIdentifier: Int] = [:]
    private var nextID: Int = 0

    public init() {}

    /// The stable id for `object`, assigning a fresh one on first sight.
    public mutating func id(for object: ObjectIdentifier) -> Int {
        if let existing = ids[object] { return existing }
        let assigned = nextID
        nextID += 1
        ids[object] = assigned
        return assigned
    }

    /// Forgets `object`'s id (call once its touch has ended/been cancelled) so the underlying
    /// dictionary doesn't grow unboundedly over a long session.
    public mutating func release(_ object: ObjectIdentifier) {
        ids.removeValue(forKey: object)
    }

    /// Number of touches currently tracked; exposed for tests.
    public var count: Int { ids.count }
}
