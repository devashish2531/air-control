import Foundation

/// `modifiers` (C→H). spec §3.4.5: "`flags` [enum(cmd|opt|ctrl|shift|fn|capsLock)] — absolute set
/// currently held/locked; host diffs against its current set and posts `flagsChanged` for each
/// changed modifier key."
public struct Modifiers: Codable, Sendable, Equatable {
    public var flags: KeyModifiers

    public init(flags: KeyModifiers) {
        self.flags = flags
    }
}
