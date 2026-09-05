import Foundation

/// Known optional-feature strings advertised in `hello.capabilities` / `helloAck.capabilities`.
/// spec §3.4.4: "Optional features are advertised as strings in `capabilities` on both sides (v1
/// set: `"tcp-motion-fallback"`, `"pair-binding-certs"`, `"udp-probe"`, `"unicode-text"`,
/// `"macro-scripts"`)."
///
/// The wire field itself is `[String]` (see `Hello.capabilities`, `HelloAck.capabilities`), not
/// `[Capability]`, so a peer's capability the current build does not recognize still round-trips
/// (spec §3.7: "Additive changes ... do not bump the version; receivers ignore what they do not
/// know"). Use `Capability(rawValue:)` / `.rawValue` to bridge to/from the raw strings.
public enum Capability: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// Motion falls back to TCP batch frames when the UDP path looks unhealthy (§3.5.8).
    case tcpMotionFallback = "tcp-motion-fallback"
    /// The TLS exporter for pairing proof binding is unavailable; certificate fingerprints alone
    /// bind the proof (§3.2.3 contingency).
    case pairBindingCerts = "pair-binding-certs"
    /// The UDP latency/health probe of §3.5.8 is supported.
    case udpProbe = "udp-probe"
    /// Non-ASCII text insertion is supported end-to-end (§3.4.5 `text`).
    case unicodeText = "unicode-text"
    /// Script/shortcut macro kinds (`appleScript`, `shellCommand`, `runShortcut`) are supported
    /// (§5.5).
    case macroScripts = "macro-scripts"
}
