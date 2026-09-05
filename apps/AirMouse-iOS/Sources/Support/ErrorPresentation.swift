// Support/ErrorPresentation.swift
// The iOS-side error copy table from spec §9 "Error handling and UX copy". English copy there
// is final for v1 — reproduced verbatim. Mac-only rows (E-MAC-*) are out of scope for this
// module. Peer `error` messages without a mapping fall back to `.generic(code:)` per spec §9's
// closing rule ("Connection problem / <code>").
//
// `AirMouseCore.AirMouseError` (arch §8 "Error taxonomy") is the eventual source of these values
// on the wire, but that type does not exist yet in the concurrently-developed kit, so this module
// works from spec §9 directly and keeps its own minimal `AppError` — a networking agent can map
// its `AirMouseError` to this enum once `AirMouseCore` lands.

import SwiftUI

/// How an error is surfaced, per the "Where" column of spec §9.
public enum ErrorPresentationStyle: Sendable, Equatable {
    /// Blocking `Alert` with title, message, and action buttons.
    case alert
    /// Non-blocking banner, typically pinned to the top of a screen.
    case banner
    /// Small persistent status badge (e.g. "Elevated latency").
    case badge
    /// Transient toast that auto-dismisses.
    case toast
    /// Inline static text with no dismiss affordance (e.g. Settings › Gyro).
    case inline
}

/// A recovery action offered on an error presentation. Carries only a stable identity and
/// display title — the *effect* of each action (open Settings, retry the connection, navigate to
/// Scan QR, …) is wired by whichever feature presents the error, since this module does not own
/// navigation or connection control.
public enum RecoveryAction: String, Sendable, Equatable, CaseIterable {
    case openSettings
    case retry
    case scanQR
    case pasteLink
    case checkPermission
    case howToUseHotspot
    case tryAgain
    case openAppStore
    case cancel
    case forgetMac
    case ok
    case trim
    case reconnect
    case copyCommand

    /// English button title (spec §9; "Action" is the primary button unless noted).
    public var title: String {
        switch self {
        case .openSettings: return String(localized: "Open Settings", comment: "Error recovery action: deep-links to iOS Settings for this app")
        case .retry: return String(localized: "Retry", comment: "Error recovery action: retries the failed connection attempt")
        case .scanQR: return String(localized: "Scan QR", comment: "Error recovery action: navigates to the QR scanner")
        case .pasteLink: return String(localized: "Paste link", comment: "Error recovery action: opens the paste-pairing-link field")
        case .checkPermission: return String(localized: "Check permission", comment: "Error recovery action: re-checks Local Network permission")
        case .howToUseHotspot: return String(localized: "How to use a hotspot", comment: "Error recovery action: opens hotspot help")
        case .tryAgain: return String(localized: "Try again", comment: "Error recovery action: dismisses and lets the user rescan")
        case .openAppStore: return String(localized: "Open App Store", comment: "Error recovery action: opens the App Store listing")
        case .cancel: return String(localized: "Cancel", comment: "Error recovery action: cancels reconnect and returns to Devices")
        case .forgetMac: return String(localized: "Forget Mac", comment: "Error recovery action: forgets the trusted host")
        case .ok: return String(localized: "OK", comment: "Error recovery action: dismisses the alert")
        case .trim: return String(localized: "Trim", comment: "Error recovery action: trims text to the maximum length")
        case .reconnect: return String(localized: "Reconnect", comment: "Error recovery action: reconnects after a rate-limit disconnect")
        case .copyCommand: return String(localized: "Copy", comment: "Error recovery action: copies a command to the clipboard")
        }
    }
}

/// A fully-resolved error ready to present: style, exact copy, and the recovery actions offered.
public struct ErrorPresentation: Sendable, Identifiable, Equatable {
    public let id: String
    public let style: ErrorPresentationStyle
    public let title: String
    public let message: String
    public let actions: [RecoveryAction]

    public init(id: String, style: ErrorPresentationStyle, title: String, message: String, actions: [RecoveryAction]) {
        self.id = id
        self.style = style
        self.title = title
        self.message = message
        self.actions = actions
    }

    public static func == (lhs: ErrorPresentation, rhs: ErrorPresentation) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.message == rhs.message && lhs.actions == rhs.actions
    }
}

/// The iOS-side cases of spec §9's table, with associated values for the interpolated pieces
/// (`<Mac>`, `<name>`, `<message>`, `<code>`). Case names are for shell/testing use; the
/// authoritative "ID" is `ErrorPresentation.id` (the `E-*` code from the spec).
public enum AppError: Sendable, Equatable {
    case localNetworkDenied
    case cameraDenied
    case noHostsFound
    case isolatedNetwork
    case connectionFailed(hostName: String)
    /// Every connect candidate refused/timed out — the Mac never answered TCP/TLS at all. Distinct
    /// from `.connectionFailed` (spec §9 E-CONN-FAILED, still used where no host name/diagnostics
    /// are available) so this one can offer a Local Network Settings deep link.
    case hostUnreachable(hostName: String)
    /// The TLS handshake completed talking to *someone*, but the certificate didn't pin to the
    /// fingerprint this device expected (reconnect to a previously-trusted Mac whose identity
    /// changed) — as opposed to `.pairingFingerprintMismatch`, which is the same failure during a
    /// fresh QR pairing attempt (spec §9 E-PAIR-FP already covers that case with its own copy).
    case tlsVerificationFailed(hostName: String)
    case pairingURLInvalid
    case pairingVersionMismatch
    case pairingFingerprintMismatch
    case pairingExpired
    /// The host rejected the pairing proof itself (wrong code), as opposed to the secret having
    /// expired — spec §9's table coalesces both under E-PAIR-EXPIRED, but the diagnostics work here
    /// distinguishes them so a mistyped/misread code doesn't tell the user to rescan a fresh code
    /// that wouldn't have helped.
    case pairingWrongCode
    case pairingRateLimited
    case pairingDeviceLimit
    case pairingHostProofInvalid
    case authUntrusted
    case authRevoked
    case versionAppOutdated
    case versionHelperOutdated
    case reconnecting(hostName: String)
    case udpFallback
    case pausedOnMac
    case accessibilityMissing
    case macroBlocked
    case macroFailed(name: String, message: String)
    case macroTimeout(name: String)
    case macroNotFound
    case textTooLong
    case rateLimited
    case gyroUnavailable
    case gyroCalibrating
    /// Fallback for a peer `error` message with no local mapping (spec §9, closing rule).
    case generic(code: String)

    public var presentation: ErrorPresentation {
        switch self {
        case .localNetworkDenied:
            return ErrorPresentation(
                id: "E-LOCALNET", style: .alert,
                title: String(localized: "Local network access is off"),
                message: String(localized: "Air Mouse can't see your Mac until you allow Local Network access in Settings."),
                actions: [.openSettings])
        case .cameraDenied:
            return ErrorPresentation(
                id: "E-CAMERA", style: .alert,
                title: String(localized: "Camera access needed"),
                message: String(localized: "Allow camera access to scan the pairing code, or paste the pairing link instead."),
                actions: [.openSettings, .pasteLink])
        case .noHostsFound:
            return ErrorPresentation(
                id: "E-NOHOSTS", style: .alert,
                title: String(localized: "No Macs found yet"),
                message: String(localized: "Is the Air Mouse helper running on your Mac? Are both devices on the same Wi-Fi? Is Local Network access allowed?"),
                actions: [.scanQR, .checkPermission])
        case .isolatedNetwork:
            return ErrorPresentation(
                id: "E-ISOLATED", style: .alert,
                title: String(localized: "This network keeps devices apart"),
                message: String(localized: "Devices on this Wi-Fi can't see each other (AP isolation). Turn on Personal Hotspot on this iPhone and join it from your Mac."),
                actions: [.retry, .howToUseHotspot])
        case .connectionFailed(let hostName):
            return ErrorPresentation(
                id: "E-CONN-FAILED", style: .alert,
                title: String(localized: "Couldn't reach \(hostName)"),
                message: String(localized: "Make sure the helper is running and both devices are on the same network."),
                actions: [.retry, .scanQR])
        case .hostUnreachable(let hostName):
            return ErrorPresentation(
                id: "E-CONN-UNREACHABLE", style: .alert,
                title: String(localized: "Couldn't reach \(hostName)"),
                message: String(localized: "Make sure your iPhone and Mac are on the same Wi-Fi and that Local Network access is allowed for Air Mouse in Settings › Privacy & Security › Local Network."),
                actions: [.openSettings, .retry])
        case .tlsVerificationFailed(let hostName):
            return ErrorPresentation(
                id: "E-TLS-MISMATCH", style: .alert,
                title: String(localized: "Couldn't verify \(hostName)"),
                message: String(localized: "Its certificate didn't match what Air Mouse expected. If you reinstalled or reset the Mac helper, forget this Mac and pair again."),
                actions: [.forgetMac, .scanQR])
        case .pairingURLInvalid:
            return ErrorPresentation(
                id: "E-PAIR-URL", style: .alert,
                title: String(localized: "That's not an Air Mouse code"),
                message: String(localized: "Scan the QR shown by 'Pair new device' in the Air Mouse menu on your Mac."),
                actions: [.tryAgain])
        case .pairingVersionMismatch:
            return ErrorPresentation(
                id: "E-PAIR-VERSION", style: .alert,
                title: String(localized: "Update Air Mouse"),
                message: String(localized: "This pairing code comes from a newer Mac helper. Update the iPhone app to pair."),
                actions: [.openAppStore])
        case .pairingFingerprintMismatch:
            return ErrorPresentation(
                id: "E-PAIR-FP", style: .alert,
                title: String(localized: "Security check failed"),
                message: String(localized: "The Mac that answered isn't the one that showed this code. Pairing was cancelled."),
                actions: [.scanQR])
        case .pairingExpired:
            return ErrorPresentation(
                id: "E-PAIR-EXPIRED", style: .alert,
                title: String(localized: "Pairing code expired"),
                message: String(localized: "Codes work for 60 seconds. Click 'Pair new device' on your Mac to show a fresh one."),
                actions: [.scanQR])
        case .pairingWrongCode:
            return ErrorPresentation(
                id: "E-PAIR-WRONGCODE", style: .alert,
                title: String(localized: "Wrong pairing code"),
                message: String(localized: "Try scanning again."),
                actions: [.scanQR])
        case .pairingRateLimited:
            return ErrorPresentation(
                id: "E-PAIR-RATELIMIT", style: .alert,
                title: String(localized: "Too many attempts"),
                message: String(localized: "Wait a minute, then show a new code on your Mac."),
                actions: [.ok])
        case .pairingDeviceLimit:
            return ErrorPresentation(
                id: "E-PAIR-FULL", style: .alert,
                title: String(localized: "Mac device limit reached"),
                message: String(localized: "This Mac already trusts 20 devices. Remove one in Trusted Devices on the Mac."),
                actions: [.ok])
        case .pairingHostProofInvalid:
            return ErrorPresentation(
                id: "E-PAIR-HOSTPROOF", style: .alert,
                title: String(localized: "Security check failed"),
                message: String(localized: "Your Mac couldn't prove it showed this code. Pairing was cancelled."),
                actions: [.scanQR])
        case .authUntrusted:
            return ErrorPresentation(
                id: "E-AUTH-UNTRUSTED", style: .alert,
                title: String(localized: "Not paired with this Mac"),
                message: String(localized: "Scan the pairing code on the Mac to connect."),
                actions: [.scanQR])
        case .authRevoked:
            return ErrorPresentation(
                id: "E-AUTH-REVOKED", style: .alert,
                title: String(localized: "This Mac no longer trusts this device"),
                message: String(localized: "Pair again to reconnect, or forget this Mac."),
                actions: [.scanQR, .forgetMac])
        case .versionAppOutdated:
            return ErrorPresentation(
                id: "E-VERSION-APP", style: .alert,
                title: String(localized: "Update the Air Mouse app"),
                message: String(localized: "Your Mac's helper speaks a newer protocol."),
                actions: [.openAppStore])
        case .versionHelperOutdated:
            return ErrorPresentation(
                id: "E-VERSION-HELPER", style: .alert,
                title: String(localized: "Update the Mac helper"),
                message: String(localized: "Open Air Mouse on your Mac and choose Check for Updates, or run brew upgrade --cask air-mouse."),
                actions: [.ok])
        case .reconnecting(let hostName):
            return ErrorPresentation(
                id: "E-RECONNECTING", style: .banner,
                title: String(localized: "Reconnecting to \(hostName)…"),
                message: "",
                actions: [.cancel])
        case .udpFallback:
            return ErrorPresentation(
                id: "E-UDP-FALLBACK", style: .badge,
                title: String(localized: "Elevated latency"),
                message: String(localized: "Fast motion packets are being blocked on this network; motion is using the reliable channel."),
                actions: [])
        case .pausedOnMac:
            return ErrorPresentation(
                id: "E-PAUSED", style: .banner,
                title: String(localized: "Paused on Mac — input is ignored until you resume it from the Air Mouse menu."),
                message: "",
                actions: [])
        case .accessibilityMissing:
            return ErrorPresentation(
                id: "E-NOAX", style: .banner,
                title: String(localized: "Mac needs Accessibility permission"),
                message: String(localized: "Open Air Mouse on the Mac and follow the setup to allow it to control the cursor."),
                actions: [])
        case .macroBlocked:
            return ErrorPresentation(
                id: "E-MACRO-BLOCKED", style: .toast,
                title: String(localized: "Blocked by Mac policy"),
                message: "",
                actions: [])
        case .macroFailed(let name, let message):
            return ErrorPresentation(
                id: "E-MACRO-FAILED", style: .toast,
                title: String(localized: "\(name) failed: \(message)"),
                message: "",
                actions: [])
        case .macroTimeout(let name):
            return ErrorPresentation(
                id: "E-MACRO-TIMEOUT", style: .toast,
                title: String(localized: "\(name) timed out"),
                message: "",
                actions: [])
        case .macroNotFound:
            return ErrorPresentation(
                id: "E-MACRO-NOTFOUND", style: .toast,
                title: String(localized: "That macro was removed on the Mac"),
                message: "",
                actions: [])
        case .textTooLong:
            return ErrorPresentation(
                id: "E-TEXT-TOOLONG", style: .alert,
                title: String(localized: "Text too long"),
                message: String(localized: "Send up to 16,000 characters at a time."),
                actions: [.trim])
        case .rateLimited:
            return ErrorPresentation(
                id: "E-RATE", style: .alert,
                title: String(localized: "Disconnected"),
                message: String(localized: "The Mac received too many commands at once and closed the connection."),
                actions: [.reconnect])
        case .gyroUnavailable:
            return ErrorPresentation(
                id: "E-GYRO-NONE", style: .inline,
                title: String(localized: "This device has no gyroscope, so Air Mouse mode isn't available."),
                message: "",
                actions: [])
        case .gyroCalibrating:
            return ErrorPresentation(
                id: "E-GYRO-CAL", style: .inline,
                title: String(localized: "Calibrating… keep the phone steady for a second."),
                message: "",
                actions: [])
        case .generic(let code):
            return ErrorPresentation(
                id: "E-GENERIC", style: .alert,
                title: String(localized: "Connection problem"),
                message: code,
                actions: [.reconnect])
        }
    }
}

// MARK: - Presentation modifier

/// Presents an `AppError?` binding as either a blocking `alert` (for `.alert`-style errors) or a
/// lightweight top banner (for `.banner`/`.badge`/`.toast`), matching spec §9's "Where" column.
/// `.inline` styles are not presented by this modifier — screens render them directly as static
/// text (e.g. Settings › Gyro, spec §9 E-GYRO-NONE).
public struct AppErrorPresentationModifier: ViewModifier {
    @Binding var error: AppError?
    let onAction: (RecoveryAction) -> Void

    public func body(content: Content) -> some View {
        let presentation = error?.presentation
        content
            .alert(
                presentation?.title ?? "",
                isPresented: Binding(
                    get: { presentation?.style == .alert },
                    set: { if !$0 { error = nil } }
                ),
                presenting: presentation?.style == .alert ? presentation : nil
            ) { presented in
                ForEach(presented.actions, id: \.self) { action in
                    Button(action.title) {
                        onAction(action)
                        error = nil
                    }
                }
                if presented.actions.isEmpty {
                    Button(RecoveryAction.ok.title, role: .cancel) { error = nil }
                }
            } message: { presented in
                Text(presented.message)
            }
            .overlay(alignment: .top) {
                if let presentation, presentation.style == .banner || presentation.style == .badge || presentation.style == .toast {
                    ErrorBannerView(presentation: presentation, onAction: { action in
                        onAction(action)
                        error = nil
                    })
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityElement(children: .combine)
                }
            }
            .animation(.default, value: presentation?.id)
    }
}

private struct ErrorBannerView: View {
    let presentation: ErrorPresentation
    let onAction: (RecoveryAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(presentation.title)
                .font(.subheadline.weight(.semibold))
            if !presentation.message.isEmpty {
                Text(presentation.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !presentation.actions.isEmpty {
                HStack {
                    ForEach(presentation.actions, id: \.self) { action in
                        Button(action.title) { onAction(action) }
                            .font(.footnote.weight(.semibold))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
    }
}

public extension View {
    /// Presents `error` per spec §9. See `AppErrorPresentationModifier`.
    func appErrorPresentation(_ error: Binding<AppError?>, onAction: @escaping (RecoveryAction) -> Void = { _ in }) -> some View {
        modifier(AppErrorPresentationModifier(error: error, onAction: onAction))
    }
}
