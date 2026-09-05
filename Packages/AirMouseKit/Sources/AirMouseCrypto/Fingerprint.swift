import CryptoKit
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A certificate "fingerprint" (FP): SHA-256 over the DER-encoded X.509 certificate bytes
/// (spec §2 glossary, line: `"fingerprint" (FP) = SHA-256 over the DER-encoded X.509 certificate
/// (SecCertificateCopyData), 32 bytes`).
///
/// This is the sole basis of trust in the protocol (spec §3.2.1): the client pins the host FP from the
/// pairing QR / Keychain, and the host looks up the client FP in its trusted-device store. `Fingerprint`
/// is deliberately not `CustomStringConvertible` (arch §3.1 rule 2: "none is CustomStringConvertible, so
/// an accidental interpolation prints the type name, not bytes") even though a fingerprint is not
/// secret — the trusted store's shape is still something we don't want appearing in logs by accident;
/// use `hexString`/`shortLogPrefix`/`txtRecordPrefix` explicitly wherever a fingerprint must be rendered.
public struct Fingerprint: Sendable, Hashable {
    /// A fingerprint is always the 32-byte output of SHA-256.
    public static let byteCount = 32

    /// The raw 32 SHA-256 bytes.
    public let bytes: [UInt8]

    /// Constructs a fingerprint directly from 32 already-hashed bytes (e.g. decoded from storage).
    /// Returns `nil` if `bytes.count != 32`.
    public init?(bytes: [UInt8]) {
        guard bytes.count == Self.byteCount else { return nil }
        self.bytes = bytes
    }

    /// Computes the fingerprint of a DER-encoded certificate (spec definition above).
    public init(certificateDER: [UInt8]) {
        let digest = SHA256.hash(data: certificateDER)
        self.bytes = Array(digest)
    }

    /// Computes the fingerprint of a DER-encoded certificate (spec definition above).
    public init(certificateDER: Data) {
        self.init(certificateDER: Array(certificateDER))
    }

    /// Parses a full 64-character lowercase-or-uppercase hex string into a fingerprint.
    public init?(hexString: String) {
        guard let decoded = Fingerprint.parseHex(hexString), decoded.count == Self.byteCount else {
            return nil
        }
        self.bytes = decoded
    }

    /// Full hex representation (64 lowercase hex characters), suitable for the trusted-device JSON
    /// records (spec §3.2.4) and diagnostics UI where the whole value is intentionally shown to the user.
    public var hexString: String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// The 8-hex-character (4-byte) prefix used for log lines (spec §7.4 / OSLog rules §7.4:
    /// "all peer identifiers as `privacy: .private` except FP prefixes (8 hex) which are `.public`").
    /// Never log more of a fingerprint than this.
    public var shortLogPrefix: String {
        bytes.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    /// The first 16 bytes of the fingerprint, b64u-encoded — the exact value carried in the Bonjour
    /// TXT record's `fp` key (spec §3.1.2: "First 16 bytes of the host certificate FP", b64u, 22 chars).
    /// This is a *hint* only; trust is decided by the full pinned certificate during TLS (§3.1.2, §3.2.4).
    public var txtRecordHint: String {
        Base64URL.encode(Array(bytes.prefix(16)))
    }

    /// Constant-time equality (spec §3.2.1/§3.2.2: verify blocks must compare fingerprints without
    /// leaking timing information about where a mismatch occurs).
    public static func == (lhs: Fingerprint, rhs: Fingerprint) -> Bool {
        ConstantTime.isEqual(lhs.bytes, rhs.bytes)
    }

    public func hash(into hasher: inout Hasher) {
        // Hashing (for Set/Dictionary bucketing) need not be constant-time; only equality does.
        hasher.combine(bytes)
    }

    private static func parseHex(_ string: String) -> [UInt8]? {
        let chars = Array(string)
        guard chars.count.isMultiple(of: 2) else { return nil }
        var result: [UInt8] = []
        result.reserveCapacity(chars.count / 2)
        var index = 0
        while index < chars.count {
            guard let high = chars[index].hexDigitValue, let low = chars[index + 1].hexDigitValue else {
                return nil
            }
            result.append(UInt8(high << 4 | low))
            index += 2
        }
        return result
    }
}
