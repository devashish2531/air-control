// spec §5.7.3 — OSLog subsystem com.aircontrol.helper, one category per architectural component (arch §8).
// Rules (never violate): no typed text, key characters, pairing secrets, session keys, private keys,
// full certificates, or full IP addresses at .info level or above. Peer identifiers are `.private`
// except an 8-hex fingerprint prefix, which is `.public`.
import os

/// Static `Logger` instances, one per spec §5.7.3 category. All helper code logs through these rather than
/// constructing ad-hoc `Logger`s, so the subsystem and category set stay centralized and auditable.
public enum Log {
    public static let subsystem = "com.aircontrol.helper"

    public static let net = Logger(subsystem: subsystem, category: "net")
    public static let tls = Logger(subsystem: subsystem, category: "tls")
    public static let pairing = Logger(subsystem: subsystem, category: "pairing")
    public static let session = Logger(subsystem: subsystem, category: "session")
    public static let inject = Logger(subsystem: subsystem, category: "inject")
    public static let macro = Logger(subsystem: subsystem, category: "macro")
    public static let store = Logger(subsystem: subsystem, category: "store")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}

/// Redaction helpers so call sites can't accidentally log sensitive values (spec §7.4, §5.7.3).
public enum Redact {
    /// Masks an IPv4 address to its /24 network for logging at `.info`+ (spec §5.7.3: "full IP addresses ...
    /// masked to /24"). Non-IPv4-looking input is returned as a fixed placeholder rather than logged verbatim.
    public static func maskedIPv4(_ address: String) -> String {
        let parts = address.split(separator: ".")
        guard parts.count == 4 else { return "invalid-ip" }
        return "\(parts[0]).\(parts[1]).\(parts[2]).0/24"
    }

    /// The only peer-identifying fragment allowed at `.public` privacy: the first 8 hex characters of a
    /// certificate fingerprint (spec §5.7.3).
    public static func fingerprintPrefix(_ fingerprintHex: String) -> String {
        String(fingerprintHex.prefix(8))
    }

    /// Truncates a macro result message to the 120-character cap before logging; script stdout itself is
    /// never logged (spec §3.3 ScriptRunner, §7.4).
    public static func truncatedMacroMessage(_ message: String, limit: Int = 120) -> String {
        message.count <= limit ? message : String(message.prefix(limit)) + "…"
    }
}
