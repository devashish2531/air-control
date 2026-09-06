import Foundation

/// `hostState.frontmostApp`. spec §3.4.5: "{`bundleID` str, `name` str}?".
public struct FrontmostApp: Codable, Sendable, Equatable {
    public var bundleID: String
    public var name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}
