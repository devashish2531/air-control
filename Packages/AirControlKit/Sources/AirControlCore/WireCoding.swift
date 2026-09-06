import Foundation
import AirControlProtocol

/// Shared `JSONEncoder`/`JSONDecoder` configuration for `Envelope` (de)serialization, per spec
/// §3.4.3: "`JSONEncoder` settings: `outputFormatting = [.sortedKeys, .withoutEscapingSlashes]`,
/// dates as `Int` ms since epoch, enums as their `rawValue` strings, binary fields as b64u
/// strings." Used by both `ClientSession` and `HostSession` so the two peers agree byte-for-byte.
enum WireCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Int64((date.timeIntervalSince1970 * 1000).rounded()))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let millis = try container.decode(Int64.self)
            return Date(timeIntervalSince1970: Double(millis) / 1000)
        }
        return decoder
    }()

    /// Encodes one envelope to a `kind = 0x01` frame body.
    static func encodeEnvelope(_ envelope: Envelope) throws -> Data {
        try encoder.encode(envelope)
    }

    /// Decodes one `kind = 0x01` frame body to an envelope. Any decode failure (including the
    /// custom `Envelope.init(from:)`'s own translation) surfaces as `ProtocolError.badMessage`.
    static func decodeEnvelope(_ body: Data) throws -> Envelope {
        do {
            return try decoder.decode(Envelope.self, from: body)
        } catch let error as ProtocolError {
            throw error
        } catch {
            throw ProtocolError.badMessage(reason: String(describing: error))
        }
    }
}
