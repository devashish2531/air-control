import Foundation
import AirControlCrypto
import AirControlProtocol

/// Client-side pairing helper (spec §3.2.2, §3.2.3): parses a scanned `aircontrol://pair` URL and
/// produces the `pairProof` HMAC once the client has a `pairChallenge` and (if the TLS exporter
/// is unavailable) knows to fall back to the zero-exporter contingency.
public enum PairingClient: Sendable {
    /// Parses and validates a scanned pairing URL (spec §3.1.3).
    public static func parse(_ urlString: String) throws -> PairingURL {
        try PairingURL.parse(urlString)
    }

    /// Computes `proof = HMAC-SHA256(S, 0x01 ‖ binding)` (spec §3.2.3) from the QR's secret and
    /// the values observed during the handshake.
    ///
    /// - Parameters:
    ///   - secret: the QR's 16-byte `s` parameter (`PairingURL.secret`).
    ///   - exporter: the 32-byte TLS exporter secret, or `nil` if unavailable (spec §3.2.3
    ///     contingency: replaced by 32 zero bytes, and both sides then advertise
    ///     `"pair-binding-certs"`).
    ///   - nonce: `pairChallenge.nonce` (16 bytes).
    ///   - clientFingerprint: this device's own certificate fingerprint.
    ///   - hostFingerprint: the pinned host fingerprint (already verified against the QR's `fp`).
    ///   - hostID: `pairChallenge.hostID` (16 bytes).
    public static func computeProof(
        secret: Data,
        exporter: Data?,
        nonce: Data,
        clientFingerprint: Fingerprint,
        hostFingerprint: Fingerprint,
        hostID: Data
    ) throws -> Data {
        let binding = try PairingWindow.binding(
            exporter: exporter,
            nonce: nonce,
            clientFingerprint: clientFingerprint,
            hostFingerprint: hostFingerprint,
            hostID: hostID
        )
        guard let pairingSecret = PairingSecret(bytes: Array(secret), issuedAt: Date()) else {
            throw ProtocolError.invalidPairingURL(field: "s", reason: "not 16 bytes")
        }
        return Data(PairingProof.clientProof(secret: pairingSecret.hmacKey, binding: binding))
    }

    /// Verifies the host's `pairConfirm.hostProof` (spec §3.2.2: "Verify hostProof; persist host
    /// cert and metadata (trusted)"). Same binding material as `computeProof`.
    public static func verifyHostProof(
        _ hostProof: Data,
        secret: Data,
        exporter: Data?,
        nonce: Data,
        clientFingerprint: Fingerprint,
        hostFingerprint: Fingerprint,
        hostID: Data
    ) throws -> Bool {
        let binding = try PairingWindow.binding(
            exporter: exporter,
            nonce: nonce,
            clientFingerprint: clientFingerprint,
            hostFingerprint: hostFingerprint,
            hostID: hostID
        )
        guard let pairingSecret = PairingSecret(bytes: Array(secret), issuedAt: Date()) else {
            return false
        }
        return PairingProof.verifyHostProof(Array(hostProof), secret: pairingSecret.hmacKey, binding: binding)
    }
}
