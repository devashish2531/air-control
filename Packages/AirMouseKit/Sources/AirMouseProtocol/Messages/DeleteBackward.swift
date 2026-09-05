import Foundation

/// `deleteBackward` (C→H). spec §3.4.5: "`count` int 1–1000, `forward` bool (default false)."
public struct DeleteBackward: Codable, Sendable, Equatable {
    public var count: Int
    public var forward: Bool

    public init(count: Int, forward: Bool = false) {
        self.count = count
        self.forward = forward
    }
}
