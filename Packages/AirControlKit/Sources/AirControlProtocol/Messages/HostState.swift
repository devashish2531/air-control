import Foundation

/// `hostState` (H→C; full snapshot on connect and on any change). spec §3.4.5 / §11.1.
public struct HostState: Codable, Sendable, Equatable {
    /// "Pause input".
    public var paused: Bool
    /// `AXIsProcessTrusted()`.
    public var accessibility: Bool
    /// `com.apple.swipescrolldirection`.
    public var naturalScroll: Bool
    public var displays: [Display]
    public var frontmostApp: FrontmostApp?
    public var inputSource: InputSource
    /// Global AND per-device.
    public var scriptsAllowed: Bool
    public var sessionCount: Int

    public init(
        paused: Bool,
        accessibility: Bool,
        naturalScroll: Bool,
        displays: [Display],
        frontmostApp: FrontmostApp? = nil,
        inputSource: InputSource,
        scriptsAllowed: Bool,
        sessionCount: Int
    ) {
        self.paused = paused
        self.accessibility = accessibility
        self.naturalScroll = naturalScroll
        self.displays = displays
        self.frontmostApp = frontmostApp
        self.inputSource = inputSource
        self.scriptsAllowed = scriptsAllowed
        self.sessionCount = sessionCount
    }
}
