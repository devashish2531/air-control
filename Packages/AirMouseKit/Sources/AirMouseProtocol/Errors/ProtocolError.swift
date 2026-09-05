import Foundation

/// Local (non-wire) error type thrown by `AirMouseProtocol`'s decoding, framing, validation and
/// parsing APIs — framing violations (spec §3.0, §3.4.1), envelope/message decode failures
/// (spec §3.4.2), pairing URL / TXT record validation (spec §3.1.2, §3.1.3), and macro validation
/// (spec §5.5.1). Distinct from `ErrorPayload`, the *wire* `error` message payload (§3.4.5) that
/// travels between peers — this type never crosses the wire itself, but `code` maps to the same
/// `ErrorCode` namespace where the spec defines a corresponding wire code (§3.2, §3.4, §9), so a
/// caller that catches a `ProtocolError` while decoding can report the matching wire code.
public enum ProtocolError: Error, LocalizedError, Sendable, Equatable {
    /// spec §3.0 / §3.4.1: control frame body exceeded `ProtocolConstants.maxControlFrameBodyBytes`.
    case frameTooLarge(length: Int)
    /// spec §3.4.1: malformed frame (unknown `kind`, zero length, truncated header).
    case badFrame(reason: String)
    /// spec §3.4.2: envelope decoded but a required field for its `t` was missing or malformed.
    case badMessage(reason: String)
    /// spec §3.2.6 / §3.4.4: no protocol version in common between `min`/`max` ranges.
    case versionMismatch(min: Int, max: Int)
    /// spec §3.5.9 / §3.4.1: a `kind = 0x02` body was not `1 + 16·n` bytes, or `n` was outside 1...16.
    case motionBatchInvalid(reason: String)
    /// spec §3.5.2: a 16-byte motion payload could not be decoded (bad length or unknown `source`).
    case motionPayloadInvalid(reason: String)
    /// spec §3.1.2: a Bonjour TXT record dictionary failed key/size/encoding validation.
    case invalidTXTRecord(field: String, reason: String)
    /// spec §3.1.3: an `airmouse://pair` URL failed to parse or a parameter failed validation.
    case invalidPairingURL(field: String, reason: String)
    /// spec §3.1.3: a formatted pairing URL could not be made to fit `qrURLMaxBytes` even after
    /// truncating the address list to one entry.
    case pairingURLTooLarge(length: Int)
    /// spec §5.5.1: a `Macro` or macro list failed shared validation.
    case macroValidation(reason: String)

    public var errorDescription: String? {
        switch self {
        case .frameTooLarge(let length):
            "Control frame body of \(length) bytes exceeds the \(ProtocolConstants.maxControlFrameBodyBytes)-byte limit."
        case .badFrame(let reason):
            "Malformed control frame: \(reason)."
        case .badMessage(let reason):
            "Malformed control message: \(reason)."
        case .versionMismatch(let min, let max):
            "No protocol version in common (peer range \(min)...\(max))."
        case .motionBatchInvalid(let reason):
            "Malformed motion batch frame: \(reason)."
        case .motionPayloadInvalid(let reason):
            "Malformed motion payload: \(reason)."
        case .invalidTXTRecord(let field, let reason):
            "Invalid TXT record field '\(field)': \(reason)."
        case .invalidPairingURL(let field, let reason):
            "Invalid pairing URL field '\(field)': \(reason)."
        case .pairingURLTooLarge(let length):
            "Pairing URL of \(length) bytes exceeds the \(ProtocolConstants.qrURLMaxBytes)-byte limit even at one address."
        case .macroValidation(let reason):
            "Invalid macro: \(reason)."
        }
    }

    /// The wire `ErrorCode` this local error corresponds to, where the spec defines one; `nil`
    /// for errors that are purely local (e.g. macro validation, which never travels as an `error`
    /// message — it prevents an invalid `Macro` from being constructed in the first place).
    public var code: ErrorCode? {
        switch self {
        case .frameTooLarge: .frameTooLarge
        case .badFrame: .badFrame
        case .badMessage: .badMessage
        case .versionMismatch: .versionMismatch
        default: nil
        }
    }
}
