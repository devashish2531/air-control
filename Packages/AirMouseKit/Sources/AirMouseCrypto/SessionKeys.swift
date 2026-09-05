import CryptoKit
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// HKDF-SHA256 derivation of the two directional UDP motion keys from a `SessionSecret`
/// (spec §3.5.3):
///
/// ```
/// kC2H = HKDF-SHA256(ikm = secret, salt = sessionID as u32 LE (4 B), info = "airmouse-udp-c2h-v1", L = 32)
/// kH2C = HKDF-SHA256(ikm = secret, salt = sessionID as u32 LE (4 B), info = "airmouse-udp-h2c-v1", L = 32)
/// ```
///
/// Separate keys per direction make the two counters independent, so a nonce (§3.5.3: 4 zero bytes ‖
/// counter LE) is never reused under one key within a session.
public enum SessionKeys: Sendable {
    /// HKDF `info` string for the client-to-host (phone → Mac) direction (spec §3.5.3).
    // TODO(integration): move to ProtocolConstants alongside the other wire literals.
    public static let clientToHostInfo = "airmouse-udp-c2h-v1"

    /// HKDF `info` string for the host-to-client (Mac → phone) direction (spec §3.5.3).
    // TODO(integration): move to ProtocolConstants alongside the other wire literals.
    public static let hostToClientInfo = "airmouse-udp-h2c-v1"

    /// HKDF output length in bytes for each directional key (spec §3.5.3: `L = 32`).
    public static let derivedKeyByteCount = 32

    /// The two directional keys derived from one `SessionSecret` for one `sessionID`.
    public struct DirectionalKeys: Sendable {
        /// `kC2H` — used by the client to seal, and the host to open, phone→Mac motion datagrams.
        public let clientToHost: SymmetricKey
        /// `kH2C` — used by the host to seal, and the client to open, Mac→phone motion datagrams
        /// (including probe echoes, spec §3.5.8).
        public let hostToClient: SymmetricKey

        public init(clientToHost: SymmetricKey, hostToClient: SymmetricKey) {
            self.clientToHost = clientToHost
            self.hostToClient = hostToClient
        }
    }

    /// The 4-byte little-endian `sessionID`, which doubles as the HKDF `salt` (spec §3.5.3).
    public static func salt(sessionID: UInt32) -> Data {
        withUnsafeBytes(of: sessionID.littleEndian) { Data($0) }
    }

    /// Derives both directional keys for `sessionID` from `secret`.
    public static func derive(secret: SessionSecret, sessionID: UInt32) -> DirectionalKeys {
        let salt = salt(sessionID: sessionID)
        let c2h = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: secret.key,
            salt: salt,
            info: Data(clientToHostInfo.utf8),
            outputByteCount: derivedKeyByteCount
        )
        let h2c = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: secret.key,
            salt: salt,
            info: Data(hostToClientInfo.utf8),
            outputByteCount: derivedKeyByteCount
        )
        return DirectionalKeys(clientToHost: c2h, hostToClient: h2c)
    }
}
