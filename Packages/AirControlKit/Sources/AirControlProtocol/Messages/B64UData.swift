import Foundation

/// A binary value that always travels on the wire as a base64url string (spec §3.0's "b64u"),
/// e.g. `pairChallenge.nonce`, `helloAck.host.id`, `sessionKey.secret`. Wrapping these fields in
/// `B64UData` instead of leaving them as `String` gives every message payload struct a typed,
/// `Data`-backed field while `Codable` still produces exactly the b64u JSON string the spec
/// requires — no message struct needs custom `Codable` just to get this encoding right.
public struct B64UData: Sendable, Equatable, Hashable {
    public var data: Data

    public init(_ data: Data) {
        self.data = data
    }
}

extension B64UData: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let data = Data(b64u: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Not valid base64url (b64u): \(string)"
            )
        }
        self.data = data
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(data.b64u)
    }
}
