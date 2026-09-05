import Foundation

/// `Macro.tint`. spec §5.5.1: "`tint`: Tint? /*12 named*/". Named colors rather than raw RGB so
/// both platforms can map to their own semantic color assets.
public enum MacroTint: String, Codable, Sendable, Hashable, CaseIterable {
    case red
    case orange
    case yellow
    case green
    case mint
    case teal
    case cyan
    case blue
    case indigo
    case purple
    case pink
    case gray
}
