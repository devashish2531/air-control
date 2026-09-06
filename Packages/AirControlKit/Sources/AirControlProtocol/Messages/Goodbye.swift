import Foundation

/// `goodbye` (both directions). spec §3.4.5: "`reason` enum(userQuit|background|revoked|replaced|
/// hostQuit|sleep|error)."
public struct Goodbye: Codable, Sendable, Equatable {
    public var reason: GoodbyeReason

    public init(reason: GoodbyeReason) {
        self.reason = reason
    }
}
