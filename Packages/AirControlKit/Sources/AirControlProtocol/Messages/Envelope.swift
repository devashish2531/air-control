import Foundation

/// Coding keys shared by `Envelope` and `Message`'s decode/encode helpers, matching spec §3.4.2's
/// wire keys exactly: `v`, `t`, `i`, `p`.
enum EnvelopeCodingKeys: String, CodingKey {
    case v, t, i, p
}

/// The control channel's message envelope. spec §3.4.2:
/// ```json
/// { "v": 1, "t": "click", "i": 1042, "p": { "button": "left", "action": "tap", "count": 1, "modifiers": [] } }
/// ```
///
/// | Field | Type | Meaning |
/// |---|---|---|
/// | `v` | int | Protocol major version of this message (always the negotiated version after `helloAck`) |
/// | `t` | string | Message type (camelCase, spec §3.4.5) |
/// | `i` | uint32 | Sender-local monotonically increasing message id; referenced by `error.ref` and `macroResult.ref` |
/// | `p` | object | Payload; MAY be omitted when empty |
///
/// `t`/`p` are folded into `message: Message` by this type's custom `Codable` conformance, which
/// dispatches on `t` to decode the matching payload type and re-emits `t`/`p` from `message` on
/// encode — matching spec §3.4.7's sketch: "Envelope's custom Codable maps `t` + `p` to the enum
/// case; unknown `t` decodes to `.unknown(type:)` internally."
///
/// spec §3.4.2: "Unknown fields → ignored (`Codable` with optionals). Missing required fields →
/// `protocol.badMessage`, message dropped." Every payload struct here uses `Codable`'s default
/// unknown-key tolerance (no `CodingKeys` restricting to a closed set) and its default
/// missing-required-key behavior (`DecodingError.keyNotFound`, which callers should treat as
/// `protocol.badMessage`).
public struct Envelope: Sendable, Equatable {
    public var v: Int
    public var i: UInt32
    public var message: Message

    public init(v: Int, i: UInt32, message: Message) {
        self.v = v
        self.i = i
        self.message = message
    }

    /// Convenience initializer stamping the currently-negotiated protocol version.
    public init(i: UInt32, message: Message, version: ProtocolVersion = .current) {
        self.init(v: version.rawValue, i: i, message: message)
    }
}

extension Envelope: Codable {
    /// Decodes an envelope. spec §3.4.2: "Missing required fields → `protocol.badMessage`,
    /// message dropped." Any `DecodingError` raised while decoding the envelope itself or the
    /// message's payload — a missing/mistyped required field anywhere — surfaces here as
    /// `ProtocolError.badMessage` rather than a raw `DecodingError`, so callers have one error
    /// type to switch on when deciding whether to count and drop a message per §3.4.2.
    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: EnvelopeCodingKeys.self)
            v = try container.decode(Int.self, forKey: .v)
            i = try container.decode(UInt32.self, forKey: .i)
            let type = try container.decode(String.self, forKey: .t)
            message = try Message.decode(type: type, from: container)
        } catch let error as DecodingError {
            throw ProtocolError.badMessage(reason: Self.describe(error))
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _):
            "missing required field '\(key.stringValue)'"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            context.debugDescription
        @unknown default:
            "\(error)"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: EnvelopeCodingKeys.self)
        try container.encode(v, forKey: .v)
        try container.encode(i, forKey: .i)
        try container.encode(message.type, forKey: .t)
        try message.encodePayload(into: &container)
    }
}
