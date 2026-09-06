import Foundation

/// The complete control-channel message catalogue. spec §3.4.5 (message catalogue) / §3.4.7's
/// illustrative sketch:
/// ```swift
/// public enum Message: Codable, Sendable {
///     // C→H
///     case hello(Hello), pairProof(PairProof), settings(Settings), click(Click)
///     case scrollPhase(ScrollPhase), modifiers(Modifiers), key(Key), text(Text)
///     case deleteBackward(DeleteBackward), mediaKey(MediaKey), volume(Volume)
///     case macroInvoke(MacroInvoke), recenter, motionEnd, heartbeat(Heartbeat)
///     // H→C
///     case pairChallenge(PairChallenge), pairConfirm(PairConfirm), helloAck(HelloAck)
///     case sessionKey(SessionKey), hostState(HostState), macroList(MacroList)
///     case macroResult(MacroResult), pong(Pong)
///     // both
///     case error(ProtocolError), goodbye(Goodbye)
/// }
/// ```
///
/// Two deviations from the sketch's payload type names, both to avoid a clash with a type this
/// package already defines elsewhere for an unrelated role:
/// - `mediaKey`'s payload is `MediaKeyMessage`, not `MediaKey` — `Keycodes/MediaKey.swift` already
///   defines `MediaKey` as the wire's `mediaKey.key` enum (backed by `NX_KEYTYPE_*` constants).
/// - `error`'s payload is `ErrorPayload`, not `ProtocolError` — `ProtocolError` is this package's
///   local `LocalizedError` type, thrown by its own framing/decoding/validation APIs (task
///   requirement), a different role from the wire payload that travels between peers.
/// `sessionKey`'s payload is `SessionKeyMessage` (not `SessionKey`) to leave `SessionKey` free for
/// `AirControlCrypto`'s derived-key value type, per architecture §3.1's own naming.
///
/// This type does not conform to `Codable` itself (unlike the sketch) — folding `t`/`p` needs
/// `Envelope`'s coding keys, so the actual (de)serialization is the `decode(type:from:)` /
/// `encodePayload(into:)` methods below, called from `Envelope`'s `Codable` conformance.
public enum Message: Sendable, Equatable {
    // C→H
    case hello(Hello)
    case pairProof(PairProof)
    case settings(Settings)
    case click(Click)
    case scrollPhase(ScrollPhase)
    case modifiers(Modifiers)
    case key(Key)
    case text(Text)
    case deleteBackward(DeleteBackward)
    case mediaKey(MediaKeyMessage)
    case volume(Volume)
    case macroInvoke(MacroInvoke)
    case recenter
    case motionEnd
    case heartbeat(Heartbeat)

    // H→C
    case pairChallenge(PairChallenge)
    case pairConfirm(PairConfirm)
    case helloAck(HelloAck)
    case sessionKey(SessionKeyMessage)
    case hostState(HostState)
    case macroList(MacroList)
    case macroResult(MacroResult)
    case pong(Pong)

    // both
    case error(ErrorPayload)
    case goodbye(Goodbye)

    /// A message whose `t` this build does not recognize. spec §3.4.2: "Unknown `t` within the
    /// negotiated version → ignored and counted (diagnostics), never fatal." The payload is
    /// intentionally not preserved (this package has no way to know its shape); a caller that only
    /// needs to count/log unknown messages has everything it needs in `type`.
    case unknown(type: String)
}

extension Message {
    /// The wire `t` value for this case (spec §3.4.5's camelCase message names).
    public var type: String {
        switch self {
        case .hello: return "hello"
        case .pairProof: return "pairProof"
        case .settings: return "settings"
        case .click: return "click"
        case .scrollPhase: return "scrollPhase"
        case .modifiers: return "modifiers"
        case .key: return "key"
        case .text: return "text"
        case .deleteBackward: return "deleteBackward"
        case .mediaKey: return "mediaKey"
        case .volume: return "volume"
        case .macroInvoke: return "macroInvoke"
        case .recenter: return "recenter"
        case .motionEnd: return "motionEnd"
        case .heartbeat: return "heartbeat"
        case .pairChallenge: return "pairChallenge"
        case .pairConfirm: return "pairConfirm"
        case .helloAck: return "helloAck"
        case .sessionKey: return "sessionKey"
        case .hostState: return "hostState"
        case .macroList: return "macroList"
        case .macroResult: return "macroResult"
        case .pong: return "pong"
        case .error: return "error"
        case .goodbye: return "goodbye"
        case .unknown(let type): return type
        }
    }

    /// Decodes the payload for `type` from `container`'s `p` key (spec §3.4.2: `p` "MAY be
    /// omitted when empty" — the no-payload cases, `recenter`/`motionEnd`, never look at `p`).
    /// An unrecognized `type` decodes to `.unknown(type:)` rather than throwing (spec §3.4.2:
    /// "Unknown `t` ... ignored ... never fatal").
    static func decode(type: String, from container: KeyedDecodingContainer<EnvelopeCodingKeys>) throws -> Message {
        switch type {
        case "hello": return .hello(try container.decode(Hello.self, forKey: .p))
        case "pairProof": return .pairProof(try container.decode(PairProof.self, forKey: .p))
        case "settings": return .settings(try container.decode(Settings.self, forKey: .p))
        case "click": return .click(try container.decode(Click.self, forKey: .p))
        case "scrollPhase": return .scrollPhase(try container.decode(ScrollPhase.self, forKey: .p))
        case "modifiers": return .modifiers(try container.decode(Modifiers.self, forKey: .p))
        case "key": return .key(try container.decode(Key.self, forKey: .p))
        case "text": return .text(try container.decode(Text.self, forKey: .p))
        case "deleteBackward": return .deleteBackward(try container.decode(DeleteBackward.self, forKey: .p))
        case "mediaKey": return .mediaKey(try container.decode(MediaKeyMessage.self, forKey: .p))
        case "volume": return .volume(try container.decode(Volume.self, forKey: .p))
        case "macroInvoke": return .macroInvoke(try container.decode(MacroInvoke.self, forKey: .p))
        case "recenter": return .recenter
        case "motionEnd": return .motionEnd
        case "heartbeat": return .heartbeat(try container.decode(Heartbeat.self, forKey: .p))
        case "pairChallenge": return .pairChallenge(try container.decode(PairChallenge.self, forKey: .p))
        case "pairConfirm": return .pairConfirm(try container.decode(PairConfirm.self, forKey: .p))
        case "helloAck": return .helloAck(try container.decode(HelloAck.self, forKey: .p))
        case "sessionKey": return .sessionKey(try container.decode(SessionKeyMessage.self, forKey: .p))
        case "hostState": return .hostState(try container.decode(HostState.self, forKey: .p))
        case "macroList": return .macroList(try container.decode(MacroList.self, forKey: .p))
        case "macroResult": return .macroResult(try container.decode(MacroResult.self, forKey: .p))
        case "pong": return .pong(try container.decode(Pong.self, forKey: .p))
        case "error": return .error(try container.decode(ErrorPayload.self, forKey: .p))
        case "goodbye": return .goodbye(try container.decode(Goodbye.self, forKey: .p))
        default: return .unknown(type: type)
        }
    }

    /// Encodes this message's payload (if any) into `container`'s `p` key. No-payload cases
    /// (`recenter`, `motionEnd`) and `.unknown` (there is nothing to re-emit) omit `p` entirely,
    /// matching spec §3.4.2's "MAY be omitted when empty".
    func encodePayload(into container: inout KeyedEncodingContainer<EnvelopeCodingKeys>) throws {
        switch self {
        case .hello(let payload): try container.encode(payload, forKey: .p)
        case .pairProof(let payload): try container.encode(payload, forKey: .p)
        case .settings(let payload): try container.encode(payload, forKey: .p)
        case .click(let payload): try container.encode(payload, forKey: .p)
        case .scrollPhase(let payload): try container.encode(payload, forKey: .p)
        case .modifiers(let payload): try container.encode(payload, forKey: .p)
        case .key(let payload): try container.encode(payload, forKey: .p)
        case .text(let payload): try container.encode(payload, forKey: .p)
        case .deleteBackward(let payload): try container.encode(payload, forKey: .p)
        case .mediaKey(let payload): try container.encode(payload, forKey: .p)
        case .volume(let payload): try container.encode(payload, forKey: .p)
        case .macroInvoke(let payload): try container.encode(payload, forKey: .p)
        case .recenter, .motionEnd, .unknown: break
        case .heartbeat(let payload): try container.encode(payload, forKey: .p)
        case .pairChallenge(let payload): try container.encode(payload, forKey: .p)
        case .pairConfirm(let payload): try container.encode(payload, forKey: .p)
        case .helloAck(let payload): try container.encode(payload, forKey: .p)
        case .sessionKey(let payload): try container.encode(payload, forKey: .p)
        case .hostState(let payload): try container.encode(payload, forKey: .p)
        case .macroList(let payload): try container.encode(payload, forKey: .p)
        case .macroResult(let payload): try container.encode(payload, forKey: .p)
        case .pong(let payload): try container.encode(payload, forKey: .p)
        case .error(let payload): try container.encode(payload, forKey: .p)
        case .goodbye(let payload): try container.encode(payload, forKey: .p)
        }
    }
}
