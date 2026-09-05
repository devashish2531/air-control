import Foundation

/// Encodes a `kind` + body into the wire framing of spec §3.4.1: `u32 LE length ‖ u8 kind ‖ body`,
/// where `length = 1 + body.count`. Throws `ProtocolError.frameTooLarge` rather than producing an
/// oversized frame a peer would reject.
public enum FrameEncoder {
    /// Encodes `body` as a frame of the given `kind`.
    ///
    /// - Throws: `ProtocolError.frameTooLarge` if `body.count` exceeds
    ///   `ProtocolConstants.maxControlFrameBodyBytes`.
    public static func encode(kind: FrameKind, body: Data) throws -> Data {
        guard body.count <= ProtocolConstants.maxControlFrameBodyBytes else {
            throw ProtocolError.frameTooLarge(length: body.count)
        }
        let length = UInt32(1 + body.count)
        var data = Data(capacity: 4 + 1 + body.count)
        data.append(contentsOf: length.littleEndianBytes)
        data.append(kind.rawValue)
        data.append(body)
        return data
    }

    /// Convenience overload taking a `Frame` value.
    public static func encode(_ frame: Frame) throws -> Data {
        try encode(kind: frame.kind, body: frame.body)
    }
}
