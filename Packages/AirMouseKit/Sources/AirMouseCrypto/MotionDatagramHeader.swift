/// The clear (unencrypted, authenticated-as-AAD) 12-byte header of a motion datagram (spec §3.5.1):
///
/// ```
/// offset  size  field       description
/// 0       4     sessionID   u32 LE, from sessionKey; selects keys + replay window
/// 4       8     counter     u64 LE, per-direction, starts at 0, strictly increasing
/// ```
///
/// This is exactly the datagram's AAD (spec §3.5.1: "AAD = bytes 0–11 (header)"). `MotionCrypto.peekHeader`
/// parses this *without* verifying the AEAD tag, so a caller (host session logic) can look up which
/// key/replay-window to use for `sessionID` before attempting to open — parsing the header never
/// authenticates the datagram.
public struct MotionDatagramHeader: Sendable, Equatable {
    /// Header size in bytes (spec §3.5.1, bytes 0–11).
    public static let byteCount = 12

    public let sessionID: UInt32
    public let counter: UInt64

    public init(sessionID: UInt32, counter: UInt64) {
        self.sessionID = sessionID
        self.counter = counter
    }

    /// Serializes to the exact 12-byte wire layout (sessionID LE ‖ counter LE).
    public var bytes: [UInt8] {
        var result = [UInt8](repeating: 0, count: Self.byteCount)
        withUnsafeBytes(of: sessionID.littleEndian) { result.replaceSubrange(0..<4, with: $0) }
        withUnsafeBytes(of: counter.littleEndian) { result.replaceSubrange(4..<12, with: $0) }
        return result
    }

    /// Parses a 12-byte header. Returns `nil` if `bytes.count != 12`.
    public init?(bytes: some Collection<UInt8>) {
        guard bytes.count == Self.byteCount else { return nil }
        let array = Array(bytes)
        let sessionID = array[0..<4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let counter = array[4..<12].withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
        self.init(sessionID: UInt32(littleEndian: sessionID), counter: UInt64(littleEndian: counter))
    }
}
