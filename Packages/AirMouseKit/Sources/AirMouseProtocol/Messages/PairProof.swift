import Foundation

/// `pairProof` (C→H). spec §3.4.5: "`proof` b64u(32)." The proof itself —
/// `HMAC-SHA256(S, 0x01 ‖ binding)` (§3.2.3) — is computed by `AirMouseCrypto`; this is only the
/// wire envelope for the resulting 32 bytes.
public struct PairProof: Codable, Sendable, Equatable {
    public var proof: B64UData

    public init(proof: B64UData) {
        self.proof = proof
    }
}
