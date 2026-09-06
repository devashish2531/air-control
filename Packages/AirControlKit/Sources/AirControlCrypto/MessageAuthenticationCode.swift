import CryptoKit
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Adapter so a raw `[UInt8]` HMAC tag (as received over the wire and b64u-decoded, spec §3.2.3:
/// "Both values are transmitted b64u-encoded in JSON") can be passed to CryptoKit's
/// `HMAC.isValidAuthenticationCode`, which expects a `ContiguousBytes & Sequence<UInt8>` rather than a
/// bare byte array. Used only by `PairingProof`'s constant-time verification helpers.
struct MessageAuthenticationCode: ContiguousBytes, Sequence {
    private let bytes: [UInt8]

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try bytes.withUnsafeBytes(body)
    }

    func makeIterator() -> Array<UInt8>.Iterator {
        bytes.makeIterator()
    }
}
