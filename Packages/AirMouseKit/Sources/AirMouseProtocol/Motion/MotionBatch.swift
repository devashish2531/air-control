import Foundation

/// Encodes/decodes the body of a `kind = 0x02` control frame: a concatenation of 1–16 16-byte
/// motion payloads, unencrypted (TLS protects the TCP channel), with `source` unchanged and no
/// per-payload counter (TCP is already ordered). spec §3.4.1: "A `kind = 0x02` frame body is a
/// concatenation of 1–16 motion payloads (16 bytes each; length must be 1 + 16·n)." spec §3.5.9:
/// "no AEAD (TLS protects it); no counter (TCP is ordered). The host feeds them to the same motion
/// pipeline with `channel = tcp` for diagnostics."
public enum MotionBatch {
    /// spec §3.4.1 / §3.5.9: `1 ≤ n ≤ 16`.
    public static let maxPayloadsPerFrame = ProtocolConstants.motionBatchMaxPayloadsPerFrame

    /// Concatenates 1–16 motion payloads into one frame body.
    ///
    /// - Throws: `ProtocolError.motionBatchInvalid` if `payloads` is empty or has more than
    ///   `maxPayloadsPerFrame` entries.
    public static func encode(_ payloads: [MotionPayload]) throws -> Data {
        guard (1...maxPayloadsPerFrame).contains(payloads.count) else {
            throw ProtocolError.motionBatchInvalid(
                reason: "expected 1...\(maxPayloadsPerFrame) payloads, got \(payloads.count)"
            )
        }
        var data = Data(capacity: payloads.count * MotionPayload.byteCount)
        for payload in payloads {
            data.append(payload.encoded())
        }
        return data
    }

    /// Splits a `kind = 0x02` frame body back into its motion payloads.
    ///
    /// - Throws: `ProtocolError.motionBatchInvalid` if `body`'s length is not a positive multiple
    ///   of 16 bytes, or the payload count is outside `1...maxPayloadsPerFrame`.
    public static func decode(_ body: Data) throws -> [MotionPayload] {
        guard body.count > 0, body.count % MotionPayload.byteCount == 0 else {
            throw ProtocolError.motionBatchInvalid(
                reason: "body length \(body.count) is not a positive multiple of \(MotionPayload.byteCount)"
            )
        }
        let count = body.count / MotionPayload.byteCount
        guard (1...maxPayloadsPerFrame).contains(count) else {
            throw ProtocolError.motionBatchInvalid(reason: "expected 1...\(maxPayloadsPerFrame) payloads, got \(count)")
        }

        var result: [MotionPayload] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            let start = body.index(body.startIndex, offsetBy: index * MotionPayload.byteCount)
            let end = body.index(start, offsetBy: MotionPayload.byteCount)
            guard let payload = MotionPayload(data: body.subdata(in: start..<end)) else {
                throw ProtocolError.motionPayloadInvalid(reason: "unrecognized source at payload \(index)")
            }
            result.append(payload)
        }
        return result
    }
}
