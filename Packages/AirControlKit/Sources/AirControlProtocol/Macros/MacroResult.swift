import Foundation

/// `macroResult` (H→C). spec §3.4.5: "`ref` int (the `i` of the `macroInvoke`), `id` str, `ok`
/// bool, `message` str ≤ 120, `code` enum(ok|notFound|blockedByPolicy|confirmationRequired|
/// timeout|failed)."
public struct MacroResult: Codable, Sendable, Equatable {
    /// The `i` (envelope message id) of the triggering `macroInvoke`.
    public var ref: UInt32
    public var id: UUID
    public var ok: Bool
    /// ≤ 120 characters; spec §5.5.4: "the first 120 chars of stdout or stderr".
    public var message: String
    public var code: MacroResultCode

    public init(ref: UInt32, id: UUID, ok: Bool, message: String, code: MacroResultCode) {
        self.ref = ref
        self.id = id
        self.ok = ok
        self.message = message
        self.code = code
    }
}
