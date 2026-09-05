/// Opaque per-touch identity, stable across the life of one physical touch. A UIKit adapter maps
/// each `UITouch`'s `ObjectIdentifier` (or ordinal) to one of these.
public struct TouchID: Sendable, Hashable {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }
}
