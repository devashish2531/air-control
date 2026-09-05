import Foundation
import Testing
@testable import AirMouseProtocol

/// Round-trips every message type in the catalogue (spec §3.4.5 / §11.1) through
/// `ProtocolJSON`'s encoder/decoder, wrapped in an `Envelope`.
@Suite struct MessageRoundTripTests {
    static let samples: [Message] = [
        .hello(
            Hello(
                protocol: .init(min: 1, max: 1),
                capabilities: [Capability.udpProbe.rawValue, "future-unknown-capability"],
                device: .init(name: "Devashish's iPhone", model: "iPhone16,1", os: "iOS 18.6", app: "1.0"),
                pairing: false,
                macroRevision: 3,
                displayHz: 120
            )
        ),
        .pairChallenge(
            PairChallenge(
                nonce: B64UData(Data(repeating: 0x01, count: 16)),
                hostID: B64UData(Data(repeating: 0x02, count: 16)),
                hostName: "Devashish's Mac mini",
                expiresInMs: 60_000
            )
        ),
        .pairProof(PairProof(proof: B64UData(Data(repeating: 0x03, count: 32)))),
        .pairConfirm(PairConfirm(hostProof: B64UData(Data(repeating: 0x04, count: 32)), hostModel: "Mac15,6")),
        .helloAck(
            HelloAck(
                protocol: 1,
                capabilities: [Capability.udpProbe.rawValue],
                host: .init(name: "Mac mini", model: "Mac15,6", os: "macOS 15.0", helper: "1.0", id: B64UData(Data(repeating: 0x05, count: 16))),
                udpPort: ProtocolConstants.defaultUDPPort,
                heartbeatMs: ProtocolConstants.helloAckHeartbeatMsDefault,
                sessionTimeoutMs: ProtocolConstants.helloAckSessionTimeoutMsDefault,
                maxTextBytes: ProtocolConstants.helloAckMaxTextBytesDefault,
                sessionCount: 1
            )
        ),
        .sessionKey(
            SessionKeyMessage(
                sessionID: 0xDEAD_BEEF,
                secret: B64UData(Data(repeating: 0x06, count: 32)),
                validForMs: ProtocolConstants.sessionKeyValidForMsDefault
            )
        ),
        .settings(.defaults),
        .click(Click(button: .left, action: .tap, count: 1, modifiers: [])),
        .click(Click(button: .right, action: .down, count: 2, modifiers: [.command, .shift])),
        .scrollPhase(ScrollPhase(phase: .began)),
        .scrollPhase(ScrollPhase(phase: .ended, vx: 120.5, vy: -30.25, momentum: true)),
        .modifiers(Modifiers(flags: [.command, .option, .capsLock])),
        .key(Key(code: 0, char: "a", action: .tap, modifiers: [])),
        .key(Key(code: 36, char: nil, action: .down, modifiers: [.function])),
        .text(Text(s: "héllo wörld 🎉", secure: false)),
        .deleteBackward(DeleteBackward(count: 3, forward: true)),
        .mediaKey(MediaKeyMessage(key: .playPause, action: .tap)),
        .mediaKey(MediaKeyMessage(key: .illuminationDown, action: .up)),
        .volume(Volume(level: 0.5, mute: false)),
        .macroInvoke(MacroInvoke(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, confirmed: true)),
        .recenter,
        .motionEnd,
        .heartbeat(Heartbeat(seq: 42, t1: 123_456_789_012)),
        .hostState(
            HostState(
                paused: false,
                accessibility: true,
                naturalScroll: true,
                displays: [Display(id: 1, x: 0, y: 0, w: 1920, h: 1080, scale: 2, main: true)],
                frontmostApp: FrontmostApp(bundleID: "com.apple.finder", name: "Finder"),
                inputSource: InputSource(id: "com.apple.keylayout.US", ansi: true),
                scriptsAllowed: false,
                sessionCount: 1
            )
        ),
        .hostState(
            HostState(
                paused: true,
                accessibility: false,
                naturalScroll: false,
                displays: [],
                frontmostApp: nil,
                inputSource: InputSource(id: "com.apple.keylayout.ABC", ansi: false),
                scriptsAllowed: true,
                sessionCount: 0
            )
        ),
        .macroList(MacroList(revision: 1, macros: [])),
        .macroResult(
            MacroResult(
                ref: 1042,
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                ok: true,
                message: "Done",
                code: .ok
            )
        ),
        .pong(
            Pong(
                seq: 7,
                t1: 1,
                t2: 2,
                t3: 3,
                motion: Pong.MotionTiming(clientTs: 10, hostTs: 20),
                injectP50Us: 500
            )
        ),
        .pong(Pong(seq: 8, t1: 4, t2: 5, t3: 6)),
        .error(ErrorPayload(code: ErrorCode.badFrame.rawValue, message: "Frame too large", ref: 3, fatal: true)),
        .error(ErrorPayload(code: "a.future.unknown.code", message: "Something new", fatal: false)),
        .goodbye(Goodbye(reason: .userQuit)),
    ]

    @Test(arguments: samples)
    func roundTripsThroughJSON(message: Message) throws {
        let envelope = Envelope(v: ProtocolVersion.current.rawValue, i: 7, message: message)
        let data = try ProtocolJSON.makeEncoder().encode(envelope)
        let decoded = try ProtocolJSON.makeDecoder().decode(Envelope.self, from: data)

        #expect(decoded.v == envelope.v)
        #expect(decoded.i == envelope.i)
        #expect(decoded.message == envelope.message)
        #expect(decoded.message.type == message.type)
    }

    @Test func unknownMessageTypeDecodesToUnknownCaseRatherThanThrowing() throws {
        let json = #"{"v":1,"t":"somethingFromTheFuture","i":9,"p":{"whatever":1}}"#
        let envelope = try ProtocolJSON.makeDecoder().decode(Envelope.self, from: Data(json.utf8))
        #expect(envelope.message == .unknown(type: "somethingFromTheFuture"))
        #expect(envelope.message.type == "somethingFromTheFuture")
    }

    @Test func unknownTopLevelFieldsAreIgnored() throws {
        let json = #"{"v":1,"t":"recenter","i":1,"futureField":"ignored"}"#
        let envelope = try ProtocolJSON.makeDecoder().decode(Envelope.self, from: Data(json.utf8))
        #expect(envelope.message == .recenter)
    }

    @Test func noPayloadCasesOmitPOnEncode() throws {
        let data = try ProtocolJSON.makeEncoder().encode(Envelope(v: 1, i: 1, message: .recenter))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["p"] == nil)
    }

    @Test func missingRequiredFieldThrowsBadMessage() throws {
        // `click` requires `button`; omit it.
        let json = #"{"v":1,"t":"click","i":1,"p":{"action":"tap","count":1,"modifiers":[]}}"#
        #expect(throws: ProtocolError.self) {
            _ = try ProtocolJSON.makeDecoder().decode(Envelope.self, from: Data(json.utf8))
        }
    }

    @Test func encodedKeysAreSortedAndCompact() throws {
        let data = try ProtocolJSON.makeEncoder().encode(Envelope(v: 1, i: 1, message: .recenter))
        let string = String(decoding: data, as: UTF8.self)
        // .sortedKeys => i, t, v alphabetically; no pretty-print whitespace.
        #expect(string == #"{"i":1,"t":"recenter","v":1}"#)
    }

    @Test func modifiersEncodeAsAnArrayOfWireStrings() throws {
        let data = try ProtocolJSON.makeEncoder().encode(Modifiers(flags: [.command, .shift]))
        let string = String(decoding: data, as: UTF8.self)
        #expect(string.contains("cmd"))
        #expect(string.contains("shift"))
        #expect(!string.contains("capsLock"))
    }

    @Test func b64uFieldsEncodeAsPlainStrings() throws {
        let payload = PairProof(proof: B64UData(Data([0, 1, 2, 3, 4, 5])))
        let data = try ProtocolJSON.makeEncoder().encode(payload)
        let string = String(decoding: data, as: UTF8.self)
        #expect(string == #"{"proof":"AAECAwQF"}"#)
    }
}
