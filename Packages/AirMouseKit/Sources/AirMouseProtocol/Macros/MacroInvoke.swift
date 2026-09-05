import Foundation

/// `macroInvoke` (C→H). spec §3.4.5: "`id` str (UUID), `confirmed` bool." `id` is typed `UUID`
/// (not `String`) for construction safety; `Codable`'s native `UUID` support already encodes it as
/// the same UUID string the wire type calls for.
public struct MacroInvoke: Codable, Sendable, Equatable {
    public var id: UUID
    /// `true` only after the client has shown the confirmation alert (required whenever
    /// `Macro.requiresConfirmation` is set, always true for script kinds — spec §5.5.5).
    public var confirmed: Bool

    public init(id: UUID, confirmed: Bool) {
        self.id = id
        self.confirmed = confirmed
    }
}
