// spec §7 (security architecture) — all randomness in the crypto module (pairing secrets, session
// secrets, serial numbers, nonces-as-material) must come from a CSPRNG, not `SystemRandomNumberGenerator`
// (which is not documented as cryptographically secure on every platform). `SecRandomCopyBytes` is the
// Apple-platform CSPRNG exposed by Security.framework.

import Security
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Error thrown when the platform CSPRNG cannot produce randomness.
public enum SecureRandomError: Error, Sendable, Equatable {
    /// `SecRandomCopyBytes` returned a non-zero `OSStatus`.
    case generationFailed(status: Int32)
}

/// A thin, `Sendable` wrapper around the platform CSPRNG (`SecRandomCopyBytes`).
///
/// Used throughout `AirMouseCrypto` for pairing secrets (spec §3.2.1), session secrets (spec §3.5.3),
/// certificate serial numbers (spec §3.2.1), and nonces where a fresh value (rather than a derived one)
/// is required.
public enum SecureRandom: Sendable {
    /// Returns `count` cryptographically-random bytes.
    public static func bytes(count: Int) throws -> [UInt8] {
        precondition(count >= 0, "count must be non-negative")
        guard count > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: count)
        let status = buffer.withUnsafeMutableBytes { pointer in
            SecRandomCopyBytes(kSecRandomDefault, count, pointer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw SecureRandomError.generationFailed(status: status)
        }
        return buffer
    }

    /// Returns `count` cryptographically-random bytes as `Data`.
    public static func data(count: Int) throws -> Data {
        Data(try bytes(count: count))
    }

    /// Returns a random `UInt32`, e.g. for candidate `sessionID`s (spec §3.5.5: "u32 random, collision
    /// checked against live sessions").
    public static func uint32() throws -> UInt32 {
        let raw = try bytes(count: 4)
        return raw.withUnsafeBytes { $0.load(as: UInt32.self) }
    }

    /// Returns a random `UInt64`.
    public static func uint64() throws -> UInt64 {
        let raw = try bytes(count: 8)
        return raw.withUnsafeBytes { $0.load(as: UInt64.self) }
    }
}
