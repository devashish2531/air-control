import Foundation
import AirMouseCrypto
import AirMouseProtocol

/// Host-side pairing window model (spec §3.2.1, §3.2.2, §3.2.6): secret generation, 60 s
/// expiry/regeneration while the window stays open, a 3-bad-proof lockout, and QR `PairingURL`
/// composition. A pure value type driven by an explicit `now: Date` on every call (arch §3.1:
/// no timers inside the kit) — the host app's menu-bar `PairingService` actor owns the actual
/// 60 s regeneration timer and calls `regenerateIfExpired(now:)` on each tick (or simply on next
/// use; regeneration is idempotent and lazy).
public struct PairingWindow: Sendable, Equatable {
    /// The result of feeding one `pairProof` attempt through the window (spec §3.2.6).
    public enum ProofOutcome: Sendable, Equatable {
        /// The proof matched; the window is now closed (secret consumed) — proceed to
        /// `pairConfirm`.
        case accepted
        /// The proof did not match; attempts remain (client may retry, but only if it reconnects
        /// with a fresh proof over the same TLS session per spec §3.2.3's exporter binding).
        case wrongProofRetry
        /// The proof did not match and this was the 3rd failure (spec §7.6, §11.3): the secret is
        /// now invalidated (window closed).
        case wrongProofLockedOut
        /// No window is open, or the secret has expired (spec §3.2.6: checked *before* the HMAC
        /// compare).
        case rejected
    }

    public private(set) var secret: PairingSecret?
    public private(set) var attempts: Int = 0

    public init() {}

    /// Whether a usable (unexpired) window is currently open.
    public func isOpen(now: Date) -> Bool {
        guard let secret else { return false }
        return secret.isValid(at: now)
    }

    /// Opens a fresh window, generating a new secret (spec §3.2.2: "Pairing window opens: secret
    /// S (16 B), expiry 60 s").
    @discardableResult
    public mutating func open(now: Date = Date()) throws -> PairingSecret {
        let fresh = try PairingSecret.generate(issuedAt: now)
        secret = fresh
        attempts = 0
        return fresh
    }

    /// Closes the window early (e.g. the user dismisses the pairing sheet, or a proof was
    /// accepted/locked out).
    public mutating func close() {
        secret = nil
        attempts = 0
    }

    /// If the window is open but its secret has expired, regenerates a fresh one so a
    /// still-displayed QR keeps working (spec §7.3: "rotation ... every 60 s while window open").
    /// Does nothing if the window is already closed — a caller wanting to keep pairing available
    /// must call `open(now:)` again explicitly. Returns the fresh secret if one was generated.
    @discardableResult
    public mutating func regenerateIfExpired(now: Date = Date()) throws -> PairingSecret? {
        guard let current = secret, !current.isValid(at: now) else { return nil }
        return try open(now: now)
    }

    /// Records the outcome of verifying one `pairProof` (spec §3.2.6: "attempts++ ... after 3 →
    /// secret invalidated"). The caller performs the actual HMAC verification (`verifyClientProof`
    /// below) and passes the boolean result in; this method owns only the expiry/attempt-count
    /// policy, checked *before* the caller need bother computing the HMAC at all when there is no
    /// valid window (spec: "checked before HMAC").
    public mutating func recordProofAttempt(valid: Bool, now: Date) -> ProofOutcome {
        guard isOpen(now: now) else {
            close()
            return .rejected
        }
        if valid {
            close()
            return .accepted
        }
        attempts += 1
        if attempts >= PairingSecret.maxAttempts {
            close()
            return .wrongProofLockedOut
        }
        return .wrongProofRetry
    }

    /// Builds the pairing `binding` (spec §3.2.3) from the raw material both sides observe.
    public static func binding(
        exporter: Data?,
        nonce: Data,
        clientFingerprint: Fingerprint,
        hostFingerprint: Fingerprint,
        hostID: Data
    ) throws -> PairingBinding {
        try PairingBinding(
            exporter: exporter.map(Array.init) ?? PairingBinding.zeroExporter,
            nonce: Array(nonce),
            clientFingerprint: clientFingerprint.bytes,
            hostFingerprint: hostFingerprint.bytes,
            hostID: Array(hostID)
        )
    }

    /// Verifies a client's `pairProof` against this window's current secret (spec §3.2.2/§3.2.3).
    /// Returns `false` (never throws) if no window is open — callers should prefer
    /// `recordProofAttempt` for the full expiry+attempts policy; this is exposed standalone so a
    /// caller can compute `valid` before calling it.
    public func verifyClientProof(_ proof: Data, binding: PairingBinding) -> Bool {
        guard let secret else { return false }
        return PairingProof.verifyClientProof(Array(proof), secret: secret.hmacKey, binding: binding)
    }

    /// Computes this window's `pairConfirm.hostProof` (spec §3.2.3), for the same `binding` the
    /// accepted client proof was checked against.
    public func computeHostProof(binding: PairingBinding) -> Data? {
        guard let secret else { return nil }
        return Data(PairingProof.hostProof(secret: secret.hmacKey, binding: binding))
    }

    /// Composes the QR/manual-fallback `PairingURL` for this window's current secret (spec
    /// §3.1.3, §3.2.2), truncating the address list (never the secret) to fit the 512-byte cap.
    public func pairingURL(
        version: Int = ProtocolConstants.protocolVersion,
        hostID: Data,
        hostName: String,
        addresses: [String],
        tcpPort: Int,
        udpPort: Int? = nil,
        fingerprint: Data
    ) throws -> PairingURL {
        guard let secret else {
            throw ProtocolError.invalidPairingURL(field: "s", reason: "no pairing window is open")
        }
        return try PairingURL.truncatingToFit(
            version: version,
            hostID: hostID,
            hostName: hostName,
            addresses: addresses,
            tcpPort: tcpPort,
            udpPort: udpPort,
            fingerprint: fingerprint,
            secret: Data(secret.bytes)
        )
    }
}
