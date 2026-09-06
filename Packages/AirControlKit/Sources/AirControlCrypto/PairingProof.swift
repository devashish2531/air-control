import CryptoKit

/// HMAC-SHA256 pairing proofs (spec §3.2.3):
///
/// ```
/// proof     = HMAC-SHA256(key = S, data = 0x01 ‖ binding)      // client → host
/// hostProof = HMAC-SHA256(key = S, data = 0x02 ‖ binding)      // host → client
/// ```
///
/// `S` is the 16-byte pairing secret (`PairingSecret`); `binding` is the 128-byte `PairingBinding`.
/// Verification uses CryptoKit's `HMAC<SHA256>.isValidAuthenticationCode`, which is constant-time,
/// satisfying spec §3.2.2's "Recompute, constant-time compare" step.
public enum PairingProof: Sendable {
    /// Prefix byte for the client→host proof (spec §3.2.3: `0x01`).
    public static let clientPrefix: UInt8 = 0x01
    /// Prefix byte for the host→client proof (spec §3.2.3: `0x02`).
    public static let hostPrefix: UInt8 = 0x02

    /// HMAC-SHA256 output length.
    public static let proofLength = 32

    /// Computes the client→host proof: `HMAC-SHA256(S, 0x01 ‖ binding)`.
    public static func clientProof(secret: SymmetricKey, binding: PairingBinding) -> [UInt8] {
        Array(HMAC<SHA256>.authenticationCode(for: [clientPrefix] + binding.bytes, using: secret))
    }

    /// Computes the host→client proof: `HMAC-SHA256(S, 0x02 ‖ binding)`.
    public static func hostProof(secret: SymmetricKey, binding: PairingBinding) -> [UInt8] {
        Array(HMAC<SHA256>.authenticationCode(for: [hostPrefix] + binding.bytes, using: secret))
    }

    /// Constant-time verification of a client→host proof (spec §3.2.2: host "Recompute, constant-time
    /// compare, check expiry/attempts/rate limit" — this covers only the compare; expiry/attempts/rate
    /// limiting are `PairingSecret`/session-state concerns owned elsewhere).
    public static func verifyClientProof(_ proof: [UInt8], secret: SymmetricKey, binding: PairingBinding) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(
            MessageAuthenticationCode(proof),
            authenticating: [clientPrefix] + binding.bytes,
            using: secret
        )
    }

    /// Constant-time verification of a host→client proof (spec §3.2.2: client "Verify hostProof").
    public static func verifyHostProof(_ proof: [UInt8], secret: SymmetricKey, binding: PairingBinding) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(
            MessageAuthenticationCode(proof),
            authenticating: [hostPrefix] + binding.bytes,
            using: secret
        )
    }
}
