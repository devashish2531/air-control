import Foundation

/// `settings.pinchMode`. spec §3.4.5: "enum(keys|zoomScroll|off) | default `keys`".
public enum PinchMode: String, Codable, Sendable, Equatable, CaseIterable {
    case keys
    case zoomScroll
    case off
}
