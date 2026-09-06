import CryptoKit
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The 16-byte, QR-only pairing secret `S` (spec §3.2.1, §3.2.2, §7.3, §11.3:
/// "Pairing secret | 16 B, 60 s, 3 attempts"):
///
/// - Generated when the pairing window opens; lives in memory only, never on disk.
/// - Valid for 60 seconds from `issuedAt`; expiry is checked *before* the HMAC compare
///   (spec §3.2.6: "Pairing window closed / secret expired | Host after pairProof (checked before
///   HMAC)").
/// - The attempt counter (max 3) is session/window state owned by the host's pairing-window logic
///   (`AirControlCore`, not yet written), not by this pure value type; `PairingSecret` only models the
///   time-based half of the expiry rule via `isValid(at:)`.
public struct PairingSecret: Sendable, Equatable {
    /// Secret length (spec §3.2.1, §11.3).
    public static let byteCount = 16

    /// Validity duration from issuance (spec §3.2.1, §7.3, §11.3: "60 s").
    // TODO(integration): move to ProtocolConstants.
    public static let validityDuration: TimeInterval = 60

    /// Effective lifetime. DEBUG builds honour `AIRCONTROL_PAIR_SECRET_TTL` (seconds) so on-device test
    /// cycles, which take minutes to install and launch, can pair with a code minted earlier. Release
    /// builds always use `validityDuration` (spec §3.1.4).
    static var effectiveValidityDuration: TimeInterval {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["AIRCONTROL_PAIR_SECRET_TTL"], let seconds = TimeInterval(raw), seconds > 0 {
            return seconds
        }
        #endif
        return validityDuration
    }

    /// Maximum wrong-proof attempts before the secret is invalidated (spec §3.2.6, §7.6, §11.3: "3").
    // TODO(integration): move to ProtocolConstants.
    public static let maxAttempts = 3

    public let bytes: [UInt8]
    public let issuedAt: Date

    /// Wraps already-generated secret bytes. Returns `nil` if `bytes.count != 16`.
    public init?(bytes: [UInt8], issuedAt: Date) {
        guard bytes.count == Self.byteCount else { return nil }
        self.bytes = bytes
        self.issuedAt = issuedAt
    }

    /// Generates a fresh, CSPRNG-backed pairing secret (spec §3.2.2: "Pairing window opens: secret S
    /// (16 B)").
    public static func generate(issuedAt: Date = Date()) throws -> PairingSecret {
        PairingSecret(bytes: try SecureRandom.bytes(count: byteCount), issuedAt: issuedAt)!
    }

    /// Whether this secret is still valid (not yet expired) at `date` (spec: 60 s from issuance;
    /// spec §7.3 also notes the window rotates the secret "every 60 s while window open" — that
    /// rotation is the caller generating a *new* `PairingSecret`, not this type mutating).
    public func isValid(at date: Date) -> Bool {
        date < issuedAt.addingTimeInterval(Self.effectiveValidityDuration)
    }

    /// Usable directly as an HMAC key by `PairingProof`.
    public var hmacKey: SymmetricKey {
        SymmetricKey(data: bytes)
    }

    /// b64u encoding of the raw secret, for embedding as the `s` query parameter of the
    /// `aircontrol://pair?...` QR URL (spec §3.2.2 sequence diagram: "QR = aircontrol://pair?…"). The QR
    /// payload's other fields (addresses, host FP, etc.) and its full URL grammar are owned by
    /// `AirControlProtocol.QRPayload` (arch §3.1) — this module only encodes/decodes the secret itself.
    public var base64URLEncoded: String {
        Base64URL.encode(bytes)
    }

    /// Decodes a b64u-encoded secret (e.g. parsed out of a scanned QR URL's `s` parameter). Returns
    /// `nil` on malformed input or wrong decoded length.
    public init?(base64URLEncoded: String, issuedAt: Date) {
        guard let decoded = Base64URL.decode(base64URLEncoded) else { return nil }
        self.init(bytes: decoded, issuedAt: issuedAt)
    }
}
