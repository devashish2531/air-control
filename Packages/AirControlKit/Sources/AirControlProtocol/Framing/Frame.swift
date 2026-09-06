import Foundation

/// One decoded control-channel frame: a `kind` byte and its body, with the 4-byte length prefix
/// already consumed. spec §3.4.1.
public struct Frame: Sendable, Equatable {
    public var kind: FrameKind
    public var body: Data

    public init(kind: FrameKind, body: Data) {
        self.kind = kind
        self.body = body
    }
}
