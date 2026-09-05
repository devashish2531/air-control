import Foundation

/// Byte-offset layout of the 44-byte UDP motion datagram. spec §3.5.1:
/// ```
/// offset  size  field       description
/// 0       4     sessionID   u32 LE, from sessionKey; selects keys + replay window
/// 4       8     counter     u64 LE, per-direction, starts at 0, strictly increasing
/// 12      16    ciphertext  ChaCha20-Poly1305 encryption of the 16-byte payload
/// 28      16    tag         Poly1305 tag
/// ```
/// "AAD = bytes 0–11 (header)." This module only describes the layout (so `AirMouseCrypto` can
/// frame the datagram); it does not perform the AEAD seal/open itself (no CryptoKit import here —
/// spec §3.0 / architecture §3.1 rule 1).
public enum MotionDatagramLayout {
    public static let sessionIDOffset = 0
    public static let sessionIDSize = 4

    public static let counterOffset = sessionIDOffset + sessionIDSize
    public static let counterSize = 8

    public static let ciphertextOffset = counterOffset + counterSize
    public static let ciphertextSize = MotionPayload.byteCount

    public static let tagOffset = ciphertextOffset + ciphertextSize
    public static let tagSize = 16

    /// Total datagram size; equals `ProtocolConstants.udpDatagramSize` (44 bytes).
    public static let totalSize = tagOffset + tagSize

    /// The additional authenticated data range: the header (`sessionID ‖ counter`), bytes 0..<12.
    public static let additionalAuthenticatedDataRange = sessionIDOffset..<ciphertextOffset  // spec §3.5.1: AAD = bytes 0–11 (sessionID ‖ counter)
}
