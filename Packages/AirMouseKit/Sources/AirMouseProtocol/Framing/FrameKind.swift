import Foundation

/// The control channel's frame `kind` byte. spec §3.4.1:
/// ```
/// offset  size  field
/// 0       4     length   u32 LE — number of bytes following this field (1 + body)
/// 4       1     kind     u8: 0x01 = JSON message, 0x02 = motion batch (binary, §3.5.9)
/// 5       n     body
/// ```
/// "Unknown `kind` → `protocol.badFrame`, close."
public enum FrameKind: UInt8, Sendable, Equatable, Hashable, CaseIterable {
    /// A single JSON control-message envelope (§3.4.2).
    case json = 0x01
    /// A concatenation of 1–16 16-byte motion payloads (§3.4.1, §3.5.9), used only by the TCP
    /// motion fallback path.
    case motionBatch = 0x02
}
