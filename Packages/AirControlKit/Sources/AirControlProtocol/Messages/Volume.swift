import Foundation

/// `volume` (C→H). spec §3.4.5: "`level` num 0.0–1.0 (host quantises to 1/16 when using key
/// events), `mute` bool?."
public struct Volume: Codable, Sendable, Equatable {
    public var level: Double
    public var mute: Bool?

    public init(level: Double, mute: Bool? = nil) {
        self.level = level
        self.mute = mute
    }
}
