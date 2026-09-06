import Foundation

/// `macroList` (H→C). spec §3.4.5: "`revision` int, `macros` [Macro] (§5.5.1). Full replacement."
/// spec §5.5.6: "On connect the host compares `hello.macroRevision` and sends the list only if it
/// differs. The client replaces its cache wholesale."
public struct MacroList: Codable, Sendable, Equatable {
    public var revision: Int
    public var macros: [Macro]

    public init(revision: Int, macros: [Macro]) {
        self.revision = revision
        self.macros = macros
    }
}
