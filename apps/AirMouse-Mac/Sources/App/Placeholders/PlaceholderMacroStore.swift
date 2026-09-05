// Temporary no-op `MacroStoring` before the macro agent's `MacroEngine` actor (arch §3.3) exists.
public actor PlaceholderMacroStore: MacroStoring {
    public init() {}

    public var macroCount: Int {
        get async { 0 }
    }
}
