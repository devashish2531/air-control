import CryptoKit
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// ChaCha20-Poly1305 AEAD sealing/opening of one 16-byte motion payload into the exact 44-byte
/// datagram layout of spec §3.5.1:
///
/// ```
/// offset  size  field       description
/// 0       4     sessionID   u32 LE
/// 4       8     counter     u64 LE
/// 12      16    ciphertext  ChaCha20-Poly1305 encryption of the 16-byte payload
/// 28      16    tag         Poly1305 tag
/// ```
///
/// AAD = bytes 0–11 (the `MotionDatagramHeader`). Nonce = 4 zero bytes ‖ counter as u64 LE (12 bytes,
/// spec §3.5.3). Because the nonce is entirely determined by the (per-direction) counter and each
/// direction has its own key (`SessionKeys`), a nonce is never reused under one key within a session
/// as long as the caller (never this type) enforces strictly-increasing counters on send.
///
/// This module does not reference `AirControlProtocol.MotionPayload` (that module is being written
/// concurrently — see module header); `seal`/`open` operate on the raw 16-byte plaintext buffer.
/// Integration note: `AirControlProtocol.MotionPayload.pack(into:)`/`unpack(from:)` should produce/consume
/// exactly the bytes this type treats as an opaque payload.
public enum MotionCrypto: Sendable {
    /// Plaintext payload size (spec §3.5.2).
    // TODO(integration): move to ProtocolConstants.
    public static let payloadLength = 16

    /// Clear-header size = AAD size (spec §3.5.1, bytes 0–11).
    public static let headerLength = MotionDatagramHeader.byteCount

    /// Poly1305 tag size (spec §3.5.1).
    public static let tagLength = 16

    /// Total datagram size (spec §3.5.1, §11.3: "UDP datagram size ... 44 B fixed").
    // TODO(integration): move to ProtocolConstants.
    public static let datagramLength = headerLength + payloadLength + tagLength // 12 + 16 + 16 = 44

    /// Builds the 12-byte nonce for `counter` (spec §3.5.3: "nonce = 0x00 0x00 0x00 0x00 ‖ counter as
    /// u64 LE (8 B)").
    public static func nonceBytes(counter: UInt64) -> [UInt8] {
        var result: [UInt8] = [0, 0, 0, 0]
        withUnsafeBytes(of: counter.littleEndian) { result.append(contentsOf: $0) }
        return result
    }

    /// Parses the 12-byte clear header of a datagram without verifying its authenticity. Returns `nil`
    /// if `datagram.count != datagramLength`. Callers use this to select the (key, `ReplayWindow`) pair
    /// for `sessionID` before calling `open`.
    public static func peekHeader(datagram: some Collection<UInt8>) -> MotionDatagramHeader? {
        guard datagram.count == datagramLength else { return nil }
        return MotionDatagramHeader(bytes: Array(datagram).prefix(headerLength))
    }

    // MARK: - Seal

    /// Seals `payload` into `output`, an exactly-`datagramLength`-byte buffer supplied by the caller
    /// (the allocation-free hot-path entry point: reuse one `[UInt8]` of size 44 across every send).
    public static func seal(
        payload: [UInt8],
        sessionID: UInt32,
        counter: UInt64,
        key: SymmetricKey,
        into output: inout [UInt8]
    ) throws {
        guard payload.count == payloadLength else {
            throw MotionCryptoError.invalidPayloadLength(expected: payloadLength, actual: payload.count)
        }
        guard output.count == datagramLength else {
            throw MotionCryptoError.invalidOutputBufferLength(expected: datagramLength, actual: output.count)
        }

        let header = MotionDatagramHeader(sessionID: sessionID, counter: counter)
        let headerBytes = header.bytes
        let nonce: ChaChaPoly.Nonce
        do {
            nonce = try ChaChaPoly.Nonce(data: nonceBytes(counter: counter))
        } catch {
            throw MotionCryptoError.cryptoFailure(description: String(describing: error))
        }

        let sealed: ChaChaPoly.SealedBox
        do {
            sealed = try ChaChaPoly.seal(payload, using: key, nonce: nonce, authenticating: headerBytes)
        } catch {
            throw MotionCryptoError.cryptoFailure(description: String(describing: error))
        }

        output.replaceSubrange(0..<headerLength, with: headerBytes)
        output.replaceSubrange(headerLength..<(headerLength + payloadLength), with: sealed.ciphertext)
        output.replaceSubrange((headerLength + payloadLength)..<datagramLength, with: sealed.tag)
    }

    /// Convenience `Data` API: allocates and returns the 44-byte datagram.
    public static func seal(
        payload: Data,
        sessionID: UInt32,
        counter: UInt64,
        key: SymmetricKey
    ) throws -> Data {
        var output = [UInt8](repeating: 0, count: datagramLength)
        try seal(payload: Array(payload), sessionID: sessionID, counter: counter, key: key, into: &output)
        return Data(output)
    }

    // MARK: - Open

    /// Opens a 44-byte `datagram` with the caller-supplied `key` (already resolved for the datagram's
    /// `sessionID` — this function does not do key lookup or replay checking; see
    /// `openAuthenticated(datagram:resolveKey:window:)` for the combined convenience). Returns the
    /// 16-byte plaintext payload on success.
    public static func open(datagram: [UInt8], key: SymmetricKey) throws -> [UInt8] {
        guard datagram.count == datagramLength else {
            throw MotionCryptoError.invalidDatagramLength(expected: datagramLength, actual: datagram.count)
        }
        let headerBytes = Array(datagram[0..<headerLength])
        let ciphertext = Array(datagram[headerLength..<(headerLength + payloadLength)])
        let tag = Array(datagram[(headerLength + payloadLength)..<datagramLength])
        guard let header = MotionDatagramHeader(bytes: headerBytes) else {
            throw MotionCryptoError.invalidDatagramLength(expected: datagramLength, actual: datagram.count)
        }

        let nonce: ChaChaPoly.Nonce
        do {
            nonce = try ChaChaPoly.Nonce(data: nonceBytes(counter: header.counter))
        } catch {
            throw MotionCryptoError.cryptoFailure(description: String(describing: error))
        }

        let box: ChaChaPoly.SealedBox
        do {
            box = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        } catch {
            throw MotionCryptoError.cryptoFailure(description: String(describing: error))
        }

        do {
            let opened = try ChaChaPoly.open(box, using: key, authenticating: headerBytes)
            return Array(opened)
        } catch is CryptoKitError {
            throw MotionCryptoError.authenticationFailed
        } catch {
            throw MotionCryptoError.cryptoFailure(description: String(describing: error))
        }
    }

    /// Convenience `Data` API for `open(datagram:key:)`.
    public static func open(datagram: Data, key: SymmetricKey) throws -> Data {
        Data(try open(datagram: Array(datagram), key: key))
    }

    // MARK: - Combined open + key lookup + replay check

    /// Classifies why `openAuthenticated` did not return a payload — the "side channel" the architecture
    /// doc calls out (arch §3.1: "`open(_:keys:window:) -> MotionPayload?` + `OpenFailure` side channel")
    /// so a caller can maintain the DoS/diagnostics counters spec §3.5.1 requires ("dropped silently and
    /// counted") without losing the reason.
    public enum OpenFailure: Error, Sendable, Equatable {
        case wrongLength
        case unknownSessionID
        case authenticationFailed
        case replay
        case tooOld
    }

    /// Combined convenience: parses the header, resolves a key for its `sessionID` via `resolveKey`,
    /// opens the AEAD, and — only after authentication succeeds (spec §3.5.4) — runs the counter through
    /// `window`. Returns the 16-byte payload on success.
    ///
    /// `resolveKey` is synchronous and side-effect-free from this function's point of view; the caller
    /// (host session logic in `AirControlCore`, not yet written) owns the actual sessionID → key table.
    public static func openAuthenticated(
        datagram: [UInt8],
        resolveKey: (UInt32) -> SymmetricKey?,
        window: inout ReplayWindow
    ) -> Result<[UInt8], OpenFailure> {
        guard let header = peekHeader(datagram: datagram) else {
            return .failure(.wrongLength)
        }
        guard let key = resolveKey(header.sessionID) else {
            return .failure(.unknownSessionID)
        }
        let payload: [UInt8]
        do {
            payload = try open(datagram: datagram, key: key)
        } catch {
            return .failure(.authenticationFailed)
        }
        switch window.accept(header.counter) {
        case .accepted:
            return .success(payload)
        case .rejectedReplay:
            return .failure(.replay)
        case .rejectedTooOld:
            return .failure(.tooOld)
        }
    }
}
