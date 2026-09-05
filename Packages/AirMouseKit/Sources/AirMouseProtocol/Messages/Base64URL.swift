import Foundation

/// base64url without padding (RFC 4648 §5), used wherever the spec says "b64u". spec §3.0:
/// "Base64 | base64url without padding (RFC 4648 §5) wherever 'b64u' appears".
public extension Data {
    /// This data, base64url-encoded with no `=` padding.
    var b64u: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    /// Decodes a base64url (padded or unpadded) string. Returns `nil` for invalid input rather
    /// than throwing, matching `Data(base64Encoded:)`'s convention.
    init?(b64u string: String) {
        var standard = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = standard.count % 4
        if remainder != 0 {
            standard.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: standard) else { return nil }
        self = data
    }
}
