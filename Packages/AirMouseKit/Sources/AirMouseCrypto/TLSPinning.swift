import Security
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Extracts the leaf certificate and fingerprint from a Network.framework TLS verify block's
/// `sec_trust_t`/`SecTrust`, per spec §3.2.1's verify-block recipe:
///
/// > extract leaf via `sec_trust_copy_ref` → `SecTrustCopyCertificateChain`; compute FP
///
/// `AirMouseCrypto` does not import `Network` (only the apps and `airmouse-cli` do, arch §3.1 rule 6),
/// but `sec_trust_t` and `sec_trust_copy_ref` are declared in `Security.framework`
/// (`Security/SecProtocolTypes.h`), so this can live here and be shared by both apps' verify/challenge
/// blocks without either app re-implementing chain-length and DER extraction.
public enum TLSPinning: Sendable {
    /// Errors extracting a usable leaf certificate from a trust reference.
    public enum ExtractionError: Error, Sendable, Equatable {
        /// Spec §3.2.1: "Chain length must be exactly 1" (both host and client verify blocks).
        case unexpectedChainLength(Int)
        /// `SecTrustCopyCertificateChain` returned nothing usable.
        case noCertificateChain
    }

    /// Extracts the single leaf certificate's DER bytes from a `SecTrust`, enforcing the spec's
    /// "chain length must be exactly 1" rule (self-signed certs pinned directly, no chain to validate).
    public static func leafCertificateDER(from secTrust: SecTrust) throws -> Data {
        guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate] else {
            throw ExtractionError.noCertificateChain
        }
        guard chain.count == 1, let leaf = chain.first else {
            throw ExtractionError.unexpectedChainLength(chain.count)
        }
        return SecCertificateCopyData(leaf) as Data
    }

    /// Extracts the single leaf certificate's DER bytes from a verify block's `sec_trust_t`.
    public static func leafCertificateDER(from trust: sec_trust_t) throws -> Data {
        let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
        return try leafCertificateDER(from: secTrust)
    }

    /// Convenience: fingerprint of the single leaf certificate in a `SecTrust`.
    public static func fingerprint(from secTrust: SecTrust) throws -> Fingerprint {
        Fingerprint(certificateDER: try leafCertificateDER(from: secTrust))
    }

    /// Convenience: fingerprint of the single leaf certificate in a verify block's `sec_trust_t`.
    public static func fingerprint(from trust: sec_trust_t) throws -> Fingerprint {
        Fingerprint(certificateDER: try leafCertificateDER(from: trust))
    }
}
