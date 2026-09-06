#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// TODO(integration): `AirControlProtocol` is specified to own the canonical `Data.b64u` helper
// (arch §3.1 public API table). This module cannot import AirControlProtocol (see module header), so
// a local, self-contained implementation lives here for `PairingSecret` and `Fingerprint`'s TXT-record
// encoding (spec §3.1.2, §3.2.3: "transmitted b64u-encoded in JSON"). When wiring the modules together,
// replace call sites here with `AirControlProtocol.Data.b64u` and delete this file, or leave both if
// `AirControlCrypto` must stay independently testable.

/// RFC 4648 §5 base64url (unpadded), the encoding the spec calls "b64u" throughout §3.1–§3.2.
public enum Base64URL: Sendable {
    /// Encodes `bytes` as unpadded base64url.
    public static func encode(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Encodes `data` as unpadded base64url.
    public static func encode(_ data: Data) -> String {
        encode(Array(data))
    }

    /// Decodes an unpadded (or padded) base64url string. Returns `nil` on malformed input.
    public static func decode(_ string: String) -> [UInt8]? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return Array(data)
    }
}
