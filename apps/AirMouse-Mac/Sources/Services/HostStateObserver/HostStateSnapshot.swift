// arch §3.3 HostStateObserver row + §8 "hostState" — this struct is the input the networking agent's
// `SessionManager` serializes into the wire `hostState` message (spec §5.3.8, §5.3.9). Its shape is a
// contract with that module; keep field names stable and additive.
import CoreGraphics
import Foundation

public struct HostStateSnapshot: Sendable, Equatable, Codable {
    /// Effective natural-scroll direction after `HostSettings.naturalScrollOverride` is applied on top of
    /// the system `com.apple.swipescrolldirection` preference (spec §5.7.3, arch §6.2).
    public var naturalScrollEnabled: Bool
    public var displayTopology: DisplayTopologySnapshot
    public var isPaused: Bool
    public var isAccessibilityTrusted: Bool
    /// Bundle identifier of the frontmost app, observed via `NSWorkspace.didActivateApplicationNotification`
    /// (spec §5.3.8 FR-PR-005: emitted within 500 ms). Logged at `.debug` only, never above (spec §5.7.3).
    public var frontmostAppBundleID: String?
    public var timestamp: Date

    public init(
        naturalScrollEnabled: Bool,
        displayTopology: DisplayTopologySnapshot,
        isPaused: Bool,
        isAccessibilityTrusted: Bool,
        frontmostAppBundleID: String?,
        timestamp: Date
    ) {
        self.naturalScrollEnabled = naturalScrollEnabled
        self.displayTopology = displayTopology
        self.isPaused = isPaused
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.frontmostAppBundleID = frontmostAppBundleID
        self.timestamp = timestamp
    }
}

/// `CGRect`'s Codable conformance across SDKs is not something this module should rely on implicitly;
/// this codes it explicitly via its four components so `HostStateSnapshot` has a stable wire shape.
struct CodableRect: Codable, Sendable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = Double(rect.origin.x)
        y = Double(rect.origin.y)
        width = Double(rect.size.width)
        height = Double(rect.size.height)
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

extension DisplayTopologySnapshot: Codable {
    private enum CodingKeys: String, CodingKey {
        case displays, mainDisplayID, unionBounds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            displays: try container.decode([DisplayInfo].self, forKey: .displays),
            mainDisplayID: try container.decode(CGDirectDisplayID.self, forKey: .mainDisplayID),
            unionBounds: try container.decode(CodableRect.self, forKey: .unionBounds).cgRect
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displays, forKey: .displays)
        try container.encode(mainDisplayID, forKey: .mainDisplayID)
        try container.encode(CodableRect(unionBounds), forKey: .unionBounds)
    }
}

extension DisplayInfo: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, bounds, isMain
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(CGDirectDisplayID.self, forKey: .id),
            bounds: try container.decode(CodableRect.self, forKey: .bounds).cgRect,
            isMain: try container.decode(Bool.self, forKey: .isMain)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(CodableRect(bounds), forKey: .bounds)
        try container.encode(isMain, forKey: .isMain)
    }
}
