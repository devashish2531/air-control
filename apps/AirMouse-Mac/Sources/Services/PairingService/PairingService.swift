// PairingService — spec §3.1.3/§3.1.4 (QR/secret lifecycle), §3.2 (pairing handshake), §5.1.3
// (Pairing window UI). Owned by the networking agent (assignment: "Services/PairingService/").
//
// Owns the single `AirMouseCore.PairingWindow` (value type) lifecycle: open/close, the 60 s
// secret-regeneration-while-open rule, and QR/manual-fallback URL composition. The actual
// proof verification (`pairProof`/`pairConfirm`) happens inside `AirMouseCore.HostSession` itself
// (it is handed a *snapshot* of this window at TLS-accept time via `HostServer`/`SessionManager`,
// per that type's `init(pairingWindow:)`) — `HostSession`'s own copy enforces expiry/attempts
// against that snapshot. This service is the single source of truth `HostServer` snapshots from
// for every new unauthenticated connection, and the place `SessionManager` reports back to once a
// session it detects transitioning from unauthenticated to authenticated has consumed the secret
// (`markConsumedByPairingSuccess()`), so the QR/countdown UI reflects reality even though the
// actual HMAC compare happened inside a different actor's private copy.
import AirMouseCore
import AirMouseCrypto
import AirMouseProtocol
import Foundation

/// Disambiguates `AirMouseCore.PairingWindow` from the SwiftUI `PairingWindow` view
/// (`Features/Pairing/PairingWindow.swift`, same app target) — see this file's header.
public typealias CorePairingWindow = AirMouseCore.PairingWindow

public actor PairingService {
    /// What the Pairing window shows (spec §5.1.3: "Waiting…" / "Paired with <device>" / locked
    /// out / closed).
    public enum Status: Sendable, Equatable {
        case closed
        case waiting
        case deviceConnecting
        case paired(deviceName: String)
        case lockedOut
    }

    private var window = CorePairingWindow()
    private(set) public var status: Status = .closed

    public init() {}

    /// Opens a fresh pairing window (spec §3.1.4: "Generated when the Pairing window opens;
    /// lifetime 60 s"). Idempotent in effect if already open — this always mints a *new* secret,
    /// matching "Pair new device…" always starting a clean 60 s countdown even if a window was
    /// already showing.
    @discardableResult
    public func openWindow(now: Date = Date()) throws -> PairingSecret {
        Log.pairing.debug("PairingService.openWindow: enter")
        let secret = try window.open(now: now)
        status = .waiting
        Log.pairing.debug("PairingService.openWindow: secret minted, status=.waiting")
        return secret
    }

    public func closeWindow() {
        window.close()
        status = .closed
    }

    public func isOpen(now: Date = Date()) -> Bool {
        window.isOpen(now: now)
    }

    /// Call periodically (e.g. `SessionManager`'s 1 s ticker) while the window is displayed: mints
    /// a fresh secret if the current one expired (spec §3.1.4 "when it reaches 0 while the window
    /// is visible a new secret and QR are generated automatically"). Returns the new secret when
    /// one was minted, so the caller can re-render the QR.
    @discardableResult
    public func regenerateIfExpired(now: Date = Date()) throws -> PairingSecret? {
        guard status == .waiting || status == .deviceConnecting else { return nil }
        return try window.regenerateIfExpired(now: now)
    }

    /// A snapshot of the current window, handed to a new `HostSession` at TLS-accept time
    /// (`HostSession.init(pairingWindow:)`) for an unauthenticated (`PinningPolicy.HostDecision
    /// .pendingPairing`) connection. `nil` when no window is open.
    public func currentSnapshot(now: Date = Date()) -> CorePairingWindow? {
        window.isOpen(now: now) ? window : nil
    }

    /// `SessionManager` calls this once it observes an unauthenticated pending connection's
    /// `HostSession.currentState` transition to `.authenticated` — i.e. a `pairProof` was accepted
    /// inside that session's own snapshot of this window. Marks this service's canonical window
    /// consumed/closed (spec §3.1.4: "Consumed on the first successful `pairConfirm`") and updates
    /// the UI status.
    public func markConsumedByPairingSuccess(deviceName: String) {
        window.close()
        status = .paired(deviceName: deviceName)
    }

    /// `SessionManager` calls this when a pending connection is still exchanging `pairChallenge`/
    /// `pairProof` (spec §5.1.3 status text has no separate "connecting" state today, but the
    /// window view uses this to disable the countdown ring's "still Waiting…" copy in favor of a
    /// lighter "Device connecting…" hint).
    public func noteDeviceConnecting() {
        if status == .waiting {
            status = .deviceConnecting
        }
    }

    /// `SessionManager` calls this after a locked-out (3 wrong proofs) or expired pairing failure,
    /// so the window can show the lockout state briefly before closing (spec §3.1.4).
    public func noteLockedOut() {
        status = .lockedOut
    }

    /// Builds the QR/manual-fallback pairing URL for the currently open window (spec §3.1.3). The
    /// caller (`HostServer`) supplies the host's identity/addresses/ports — this service owns only
    /// the secret half of the payload.
    public func pairingURL(
        hostID: Data,
        hostName: String,
        addresses: [String],
        tcpPort: Int,
        udpPort: Int,
        fingerprint: Data
    ) throws -> PairingURL {
        try window.pairingURL(
            hostID: hostID,
            hostName: hostName,
            addresses: addresses,
            tcpPort: tcpPort,
            udpPort: udpPort,
            fingerprint: fingerprint
        )
    }
}
