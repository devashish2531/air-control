import Foundation

/// The `JSONEncoder`/`JSONDecoder` configuration every control message uses. spec §3.4.3:
/// "`JSONEncoder` settings: `outputFormatting = [.sortedKeys, .withoutEscapingSlashes]`, dates as
/// `Int` ms since epoch, enums as their `rawValue` strings, binary fields as b64u strings." Stable
/// key ordering (`.sortedKeys`) makes wire captures byte-for-byte reproducible across runs, and no
/// pretty-printing keeps every message on one line for `nc`/log capture.
///
/// Enum-as-rawValue and binary-as-b64u are not encoder *strategies* here — every wire enum is a
/// `String`-backed `RawRepresentable` (encodes as its raw string automatically) and every wire
/// binary field is `B64UData` (encodes as its b64u string automatically), so no custom strategy is
/// needed for either.
public enum ProtocolJSON {
    /// A fresh encoder configured per spec §3.4.3. `JSONEncoder` is not thread-safe to share
    /// across concurrent encodes, so this returns a new instance each call.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    /// A fresh decoder configured per spec §3.4.3.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
