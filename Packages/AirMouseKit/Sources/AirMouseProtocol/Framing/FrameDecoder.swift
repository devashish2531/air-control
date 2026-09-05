import Foundation

/// Incremental decoder for the control-channel framing of spec §3.4.1. Feed it arbitrary byte
/// chunks — as small as one byte, as large as many frames at once — and it yields every complete
/// frame the accumulated bytes contain, retaining any partial trailing frame for the next `feed`.
///
/// A value type (spec-wide rule: "the kit contains no actors... state machines are pure reducers");
/// the caller owns a `var` instance per connection and is responsible for its own synchronization
/// (typically one actor per connection in the apps).
public struct FrameDecoder: Sendable {
    private var buffer = Data()

    public init() {}

    /// Bytes buffered but not yet enough to form a complete frame.
    public var pendingByteCount: Int { buffer.count }

    /// Appends `bytes` to the internal buffer and returns every complete frame now available.
    ///
    /// - Throws: `ProtocolError.frameTooLarge` if a declared frame length exceeds
    ///   `ProtocolConstants.maxFrameLengthFieldValue`, or `ProtocolError.badFrame` for a
    ///   zero-length frame or an unrecognized `kind` byte. After a throw the decoder's buffer may
    ///   contain the offending bytes; the caller should discard the decoder (close the connection)
    ///   rather than continuing to feed it, matching spec §3.4.1's "connection closed".
    public mutating func feed(_ bytes: Data) throws -> [Frame] {
        buffer.append(bytes)

        var frames: [Frame] = []
        while true {
            guard buffer.count >= 4 else { break }

            let lengthStart = buffer.startIndex
            let lengthBytes = buffer[lengthStart..<buffer.index(lengthStart, offsetBy: 4)]
            guard let length = UInt32(littleEndianBytes: lengthBytes) else { break }

            guard length >= 1 else {
                throw ProtocolError.badFrame(reason: "zero-length frame")
            }
            guard length <= ProtocolConstants.maxFrameLengthFieldValue else {
                throw ProtocolError.frameTooLarge(length: Int(length) - 1)
            }

            let total = 4 + Int(length)
            guard buffer.count >= total else { break }

            let kindIndex = buffer.index(lengthStart, offsetBy: 4)
            let kindByte = buffer[kindIndex]
            guard let kind = FrameKind(rawValue: kindByte) else {
                throw ProtocolError.badFrame(reason: String(format: "unknown kind 0x%02x", kindByte))
            }

            let bodyStart = buffer.index(lengthStart, offsetBy: 5)
            let frameEnd = buffer.index(lengthStart, offsetBy: total)
            let body = buffer.subdata(in: bodyStart..<frameEnd)
            frames.append(Frame(kind: kind, body: body))

            buffer.removeSubrange(lengthStart..<frameEnd)
        }
        return frames
    }
}
