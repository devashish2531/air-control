import Foundation

/// The on-disk macro store document. spec §5.5.2: "`~/Library/Application
/// Support/AirMouseHelper/Macros.json` = `{ "schema": "macros/1", "revision": Int, "macros":
/// [Macro] }`, atomic writes, `revision` incremented on every save." Also used, with the same
/// schema, for the client's per-host macro cache (architecture §6.3).
public struct MacroDocument: Codable, Sendable, Equatable {
    /// spec §5.5.1: "`MacroList` JSON schema version `"macros/1"`."
    public static let schemaName = "macros/1"

    public var schema: String
    public var revision: Int
    public var macros: [Macro]

    public init(revision: Int, macros: [Macro]) {
        self.schema = Self.schemaName
        self.revision = revision
        self.macros = macros
    }
}
