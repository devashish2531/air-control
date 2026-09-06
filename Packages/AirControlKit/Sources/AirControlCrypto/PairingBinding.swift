/// The 128-byte channel-binding material HMACed into a pairing proof (spec §3.2.3):
///
/// ```
/// binding = exporter(32) ‖ nonce(16) ‖ clientFP(32) ‖ hostFP(32) ‖ hostID(16)      // 128 bytes
/// ```
///
/// The exporter binds the proof to the one TLS session it was computed on; the fingerprints bind it to
/// the two identities that authenticated in that handshake; the nonce supplies freshness even if the
/// exporter were constant (spec §3.2.3 contingency: "if `sec_protocol_metadata_create_secret` proves
/// unavailable ... `exporter` is replaced by 32 zero bytes"). Field lengths are validated at
/// construction so a caller cannot silently build a malformed binding.
public struct PairingBinding: Sendable, Equatable {
    /// Exporter length (spec §3.2.3: "exporter(32)").
    public static let exporterLength = 32
    /// Nonce length (spec §3.2.2: `pairChallenge { nonce (16 B), ... }`).
    public static let nonceLength = 16
    /// Fingerprint length (spec §2: FP = SHA-256, 32 bytes).
    public static let fingerprintLength = Fingerprint.byteCount
    /// Host ID length (spec §3.1.2: "Host ID: 16 random bytes").
    public static let hostIDLength = 16
    /// Total binding length: 32 + 16 + 32 + 32 + 16 = 128 bytes (spec §3.2.3).
    public static let totalLength = exporterLength + nonceLength + fingerprintLength * 2 + hostIDLength

    public let exporter: [UInt8]
    public let nonce: [UInt8]
    public let clientFingerprint: [UInt8]
    public let hostFingerprint: [UInt8]
    public let hostID: [UInt8]

    /// Field-length errors reported by `init(exporter:nonce:clientFingerprint:hostFingerprint:hostID:)`.
    public enum FieldError: Error, Sendable, Equatable {
        case exporter(expected: Int, actual: Int)
        case nonce(expected: Int, actual: Int)
        case clientFingerprint(expected: Int, actual: Int)
        case hostFingerprint(expected: Int, actual: Int)
        case hostID(expected: Int, actual: Int)
    }

    public init(
        exporter: [UInt8],
        nonce: [UInt8],
        clientFingerprint: [UInt8],
        hostFingerprint: [UInt8],
        hostID: [UInt8]
    ) throws {
        guard exporter.count == Self.exporterLength else {
            throw FieldError.exporter(expected: Self.exporterLength, actual: exporter.count)
        }
        guard nonce.count == Self.nonceLength else {
            throw FieldError.nonce(expected: Self.nonceLength, actual: nonce.count)
        }
        guard clientFingerprint.count == Self.fingerprintLength else {
            throw FieldError.clientFingerprint(expected: Self.fingerprintLength, actual: clientFingerprint.count)
        }
        guard hostFingerprint.count == Self.fingerprintLength else {
            throw FieldError.hostFingerprint(expected: Self.fingerprintLength, actual: hostFingerprint.count)
        }
        guard hostID.count == Self.hostIDLength else {
            throw FieldError.hostID(expected: Self.hostIDLength, actual: hostID.count)
        }
        self.exporter = exporter
        self.nonce = nonce
        self.clientFingerprint = clientFingerprint
        self.hostFingerprint = hostFingerprint
        self.hostID = hostID
    }

    /// The 32 zero bytes used in place of a real TLS exporter under the §3.2.3 contingency.
    public static let zeroExporter = [UInt8](repeating: 0, count: exporterLength)

    /// The exact 128-byte wire concatenation.
    public var bytes: [UInt8] {
        exporter + nonce + clientFingerprint + hostFingerprint + hostID
    }
}
