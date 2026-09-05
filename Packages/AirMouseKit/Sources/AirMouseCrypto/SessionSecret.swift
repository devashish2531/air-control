import CryptoKit
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The 32-byte, host-issued, per-TCP-connection secret from which the two directional UDP keys are
/// derived (spec §3.5.3, §7.3: "UDP session secret + kC2H/kH2C ... every TLS connection ... memory only").
///
/// Wraps a `SymmetricKey` rather than raw bytes so the material never gets an accidental
/// `CustomStringConvertible` conformance (arch §3.1 rule 2); it is never persisted and never leaves
/// the `sessionKey` control message that carries it once per connection.
public struct SessionSecret: Sendable {
    /// A session secret is always 32 bytes (spec §3.5.3: `secret` is the HKDF `ikm`).
    public static let byteCount = 32

    /// The wrapped key material, usable directly as HKDF `ikm`.
    public let key: SymmetricKey

    /// Wraps already-generated secret bytes. Returns `nil` if `bytes.count != 32`.
    public init?(bytes: [UInt8]) {
        guard bytes.count == Self.byteCount else { return nil }
        self.key = SymmetricKey(data: bytes)
    }

    /// Wraps already-generated secret bytes. Returns `nil` if `data.count != 32`.
    public init?(data: Data) {
        self.init(bytes: Array(data))
    }

    init(key: SymmetricKey) {
        self.key = key
    }

    /// Generates a fresh, CSPRNG-backed session secret — the host does this on every new TCP connection
    /// (spec §3.3.1: "A new `sessionKey` is issued on every TLS connection").
    public static func generate() throws -> SessionSecret {
        SessionSecret(key: SymmetricKey(data: try SecureRandom.bytes(count: byteCount)))
    }
}
