// Minimal protocol slots the UI shell needs from modules owned by other agents (networking, event
// injection, macros — CLAUDE.md: "write a minimal protocol in your own module and note it in your
// report" when the real type doesn't exist yet). Real conforming types (HostServer actor, EventInjector
// actor, MacroEngine actor, TrustStore actor — arch §3.3) should conform to these from their own modules;
// nothing here performs networking, CGEvent posting, keycode mapping, or macro execution.
import Foundation

// MARK: - HostServing

/// One entry in the menu's "Connected devices" submenu (spec §5.1.2).
public struct ConnectedSessionInfo: Sendable, Identifiable, Equatable {
    public var id: String
    public var deviceName: String
    public var model: String
    public var latencyMillis: Int?

    public init(id: String, deviceName: String, model: String, latencyMillis: Int?) {
        self.id = id
        self.deviceName = deviceName
        self.model = model
        self.latencyMillis = latencyMillis
    }
}

/// Surface `HostServer`/`SessionManager`/`PairingService` (arch §3.3) expose to the menu bar UI. The real
/// implementation owns `NWListener`, TLS, and session state machines — none of that belongs here.
public protocol HostServing: Sendable {
    /// Starts Bonjour advertisement + the TLS listener. Idempotent.
    func start() async
    /// Stops the listener and closes all sessions with `goodbye{hostQuit}` or similar (spec §5.1.2 Quit).
    func stop() async
    /// Snapshot of currently connected sessions, for the menu's status line and submenu (spec §5.1.2).
    var connectedSessions: [ConnectedSessionInfo] { get async }
    /// docs/08 §5.2 Overview card "server Running/Stopped". `true` once `start()` has finished
    /// binding both listeners; `false` before `start()` or after `stop()`/a bind failure.
    var isRunning: Bool { get async }
    /// docs/08 §5.2 Overview card "TCP/UDP ports". `nil` before the listener is bound (or, for the
    /// UDP hub, if that read races the bind — same caveat `HostServer`'s own loopback banner has).
    var tcpPort: UInt16? { get async }
    var udpPort: UInt16? { get async }
    /// Opens the pairing secret/window lifecycle (spec §5.1.3) and returns the QR payload string to render.
    func openPairingWindow() async throws -> String
    /// Closes the pairing window and invalidates the current secret (spec §5.1.3 "Closing invalidates the secret").
    func closePairingWindow() async
    /// Disconnects one session (menu "Disconnect", spec §5.1.2).
    func disconnect(sessionID: String) async
}

// MARK: - EventInjecting

/// Surface `EventInjector` (arch §3.3) exposes to the UI shell: only pause/resume. Everything else
/// (CGEvent posting, momentum, key repeat, keycodes) is out of scope for this module.
public protocol EventInjecting: Sendable {
    var isPaused: Bool { get async }
    /// spec §5.3.10 "Pause input" — release-all happens inside the real implementation.
    func pause() async
    func resume() async
}

// MARK: - MacroStoring

/// Surface the Macro editor's window chrome needs before it is replaced by the macro agent's real view
/// (Features/MacroEditor). Kept intentionally tiny.
public protocol MacroStoring: Sendable {
    var macroCount: Int { get async }
}

// MARK: - TrustStoring

/// One row of the Trusted Devices table (spec §5.6).
public struct TrustedDeviceRecord: Sendable, Identifiable, Equatable, Codable {
    public var id: String
    public var name: String
    public var model: String
    public var osVersion: String
    /// First 8 hex chars only — the only fingerprint fragment allowed to be displayed/logged freely (spec §5.7.3).
    public var fingerprintShort: String
    public var firstPaired: Date
    public var lastSeen: Date
    public var allowScripts: Bool
    public var revoked: Bool

    public init(
        id: String,
        name: String,
        model: String,
        osVersion: String,
        fingerprintShort: String,
        firstPaired: Date,
        lastSeen: Date,
        allowScripts: Bool,
        revoked: Bool
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.osVersion = osVersion
        self.fingerprintShort = fingerprintShort
        self.firstPaired = firstPaired
        self.lastSeen = lastSeen
        self.allowScripts = allowScripts
        self.revoked = revoked
    }
}

public enum TrustStoreError: Error, Sendable, Equatable {
    case notFound(id: String)
}

/// Surface `TrustStore` (arch §3.3, §3.2.4) exposes to the Trusted Devices window. The real actor also
/// owns Keychain certificate storage and TLS-handshake-time trust decisions — not modeled here.
public protocol TrustStoring: Sendable {
    func listDevices() async -> [TrustedDeviceRecord]
    /// Revoke: mark record revoked, delete the certificate, close the session, remove the row (spec §5.6).
    func revoke(id: String) async throws
    func revokeAll() async throws
    /// Per-device "Allow scripts" checkbox (spec §5.6); disabled in the UI when the global toggle is off.
    func setAllowScripts(_ allow: Bool, forDeviceID id: String) async throws
    /// Editable local alias (spec §5.6 table, "Name (editable local alias)"). Added beyond the literal
    /// "list/revoke records" brief because the Trusted Devices window can't satisfy the spec's Name column
    /// without it.
    func rename(id: String, to newName: String) async throws
}
