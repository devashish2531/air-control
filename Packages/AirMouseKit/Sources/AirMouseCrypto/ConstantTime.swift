#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Constant-time comparison helpers.
///
/// Used wherever the spec requires "constant-time compare" (pairing proof verification, §3.2.3;
/// fingerprint pinning, §3.2.1) to avoid timing side channels that could let an attacker recover a
/// secret or forge a proof byte-by-byte. CryptoKit's own `HMAC.isValidAuthenticationCode` is already
/// constant-time and is preferred where applicable (`PairingProof`); this type exists for the
/// remaining raw-byte comparisons (e.g. certificate fingerprints).
public enum ConstantTime: Sendable {
    /// Compares two byte sequences in constant time with respect to their *contents*.
    ///
    /// A length mismatch returns `false` immediately (lengths are not secret in this codebase — a
    /// `Fingerprint` is always exactly 32 bytes, a pairing secret always exactly 16 — so a length-based
    /// short circuit leaks nothing an attacker doesn't already know). Byte content is compared without
    /// early exit, accumulating an OR of all XOR differences.
    public static func isEqual(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for index in lhs.indices {
            difference |= lhs[index] ^ rhs[index]
        }
        return difference == 0
    }

    /// `Data`-based overload; see `isEqual(_:_:)`.
    public static func isEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        isEqual(Array(lhs), Array(rhs))
    }

    /// `ArraySlice`-based overload; see `isEqual(_:_:)`.
    public static func isEqual(_ lhs: ArraySlice<UInt8>, _ rhs: ArraySlice<UInt8>) -> Bool {
        isEqual(Array(lhs), Array(rhs))
    }
}
