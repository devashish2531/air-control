/// Typed failures from `MotionCrypto` sealing and opening.
public enum MotionCryptoError: Error, Sendable, Equatable {
    /// `seal(payload:...)` was given a plaintext payload that isn't exactly
    /// `MotionCrypto.payloadLength` (16) bytes (spec §3.5.2).
    case invalidPayloadLength(expected: Int, actual: Int)

    /// `seal(...into:)` was given an output buffer that isn't exactly `MotionCrypto.datagramLength` (44)
    /// bytes (spec §3.5.1).
    case invalidOutputBufferLength(expected: Int, actual: Int)

    /// `open(datagram:...)` was given a buffer that isn't exactly `MotionCrypto.datagramLength` (44)
    /// bytes. Per spec §3.5.1 this datagram must be dropped silently on the wire; this error is the
    /// typed signal a caller uses to do that (and to count it).
    case invalidDatagramLength(expected: Int, actual: Int)

    /// ChaCha20-Poly1305 authentication failed: the tag didn't match (tampered ciphertext, tampered
    /// header/AAD, or the wrong key). Per spec §3.5.1 this datagram must be dropped silently.
    case authenticationFailed

    /// The underlying AEAD primitive rejected the operation for a reason other than authentication
    /// (e.g. a malformed nonce/tag construction). Should not occur given this module's own inputs;
    /// exists so `seal`/`open` never need `try!`.
    case cryptoFailure(description: String)
}
