// Services/ConnectionManager/ConnectionSinks.swift
// The four output-boundary sinks other features depend on (`ControlMessageSink`,
// `MotionDatagramSink`, `KeyboardEventSink`, `RemoteCommandSink`), all forwarding to
// `ConnectionManager`'s live `ClientSessioning`. Kept as thin adapters — no wire-shape decisions
// belong here that the sink protocols' own doc comments didn't already make.

import Foundation
import AirMouseCore
import AirMouseProtocol

// MARK: - Touchpad (Features/Touchpad/ControlMessageSink.swift)

@MainActor
public final class ConnectionControlSink: ControlMessageSink {
    private unowned let manager: ConnectionManager

    public init(manager: ConnectionManager) {
        self.manager = manager
    }

    public func sendClick(_ click: Click) {
        forward { try await $0.sendClick(click) }
    }

    public func sendScrollPhase(_ phase: ScrollPhase) {
        forward { try await $0.sendScrollPhase(phase) }
    }

    public func sendSettings(_ settings: Settings) {
        forward { try await $0.sendSettings(settings) }
    }

    private func forward(_ operation: @escaping @Sendable (any ClientSessioning) async throws -> Void) {
        guard let session = manager.activeSession else { return }
        Task { try? await operation(session) }
    }
}

// MARK: - Motion (Services/MotionPublisher/MotionDatagramSink.swift)

/// spec: "must not block" the motion publisher's own executor — hops onto a detached, high-
/// priority `Task` per payload rather than awaiting inline, per this sink protocol's own doc
/// comment ("a conformer that needs to hop elsewhere ... should do so by handing the payload to
/// something like an unbounded internal queue and returning immediately").
public final class ConnectionMotionSink: MotionDatagramSink, Sendable {
    private unowned(unsafe) let manager: ConnectionManager

    @MainActor
    public init(manager: ConnectionManager) {
        self.manager = manager
    }

    public func sendMotion(_ payload: MotionPayload) {
        Task.detached(priority: .high) { [manager] in
            guard let session = await manager.activeSession else { return }
            do {
                try await session.sendMotion(payload)
            } catch {
                // Previously a bare `try?`: every failure here — most commonly `CoreError.
                // channelClosed` while the UDP channel is still coming up or has gone bad — vanished
                // with nothing to show for it. `TouchpadDebugMotionLabel`'s `sentDatagramCount`
                // only proves this method was *called*, never that anything reached the wire, so a
                // session stuck unable to send motion looked identical to a healthy one from that
                // counter alone. Surface it instead (see `DiagnosticsModel.motionSendFailureCounts`).
                await manager.recordMotionSendFailure(kind: Self.errorKind(error))
            }
        }
    }

    /// Short, developer-facing label for a `sendMotion`/`sendProbe` failure — never the error's
    /// full interpolated description (spec §7: no secrets/text in logs, and this string also feeds
    /// a DEBUG-only on-screen label the owner might photograph/screenshot).
    private static func errorKind(_ error: Error) -> String {
        if let coreError = error as? CoreError {
            return String(describing: coreError.category) + ":" + Self.caseName(coreError)
        }
        return String(describing: type(of: error))
    }

    private static func caseName(_ error: CoreError) -> String {
        switch error {
        case .protocolViolation: "protocolViolation"
        case .versionMismatch: "versionMismatch"
        case .pairingExpired: "pairingExpired"
        case .pairingInvalidProof: "pairingInvalidProof"
        case .pairingTooManyDevices: "pairingTooManyDevices"
        case .pairingHostProofInvalid: "pairingHostProofInvalid"
        case .pairingAlreadyTrusted: "pairingAlreadyTrusted"
        case .authUntrusted: "authUntrusted"
        case .authRevoked: "authRevoked"
        case .rateLimited: "rateLimited"
        case .macroBlockedByPolicy: "macroBlockedByPolicy"
        case .sessionTimedOut: "sessionTimedOut"
        case .channelClosed: "channelClosed"
        case .protocolMismatch: "protocolMismatch"
        case .internalFailure: "internalFailure"
        }
    }
}

// MARK: - Keyboard (Services/KeyboardBridge/KeyboardEventSink.swift)

@MainActor
public final class ConnectionKeyboardSink: KeyboardEventSink {
    private unowned let manager: ConnectionManager

    public init(manager: ConnectionManager) {
        self.manager = manager
    }

    public func sendKey(virtualKey: UInt16, char: String?, modifiers: KeyModifiers, isDown: Bool) {
        let key = Key(code: Int(virtualKey), char: char, action: isDown ? .down : .up, modifiers: modifiers)
        guard let session = manager.activeSession else { return }
        Task { try? await session.sendKey(key) }
    }

    public func sendText(_ text: String) {
        guard let session = manager.activeSession else { return }
        // Never log `text` (spec §7 / CLAUDE.md).
        Task { try? await session.sendText(AirMouseProtocol.Text(s: text, secure: false)) }
    }

    public func sendMediaKey(_ key: MediaKey) {
        guard let session = manager.activeSession else { return }
        Task { try? await session.sendMediaKey(MediaKeyMessage(key: key, action: .tap)) }
    }
}

// MARK: - Remote/Macros (Features/Remote/RemoteCommandSink.swift)

@MainActor
public final class ConnectionRemoteSink: RemoteCommandSink {
    private unowned let manager: ConnectionManager

    public init(manager: ConnectionManager) {
        self.manager = manager
    }

    public var frontmostAppName: String? { manager.latestHostState?.frontmostApp?.name }
    public var scriptsAllowedOnHost: Bool { manager.latestHostState?.scriptsAllowed ?? true }

    public func sendMediaKey(_ key: MediaKey) {
        guard let session = manager.activeSession else { return }
        Task { try? await session.sendMediaKey(MediaKeyMessage(key: key, action: .tap)) }
    }

    public func sendShortcut(virtualKey: UInt16, modifiers: KeyModifiers) {
        guard let session = manager.activeSession else { return }
        let key = Key(code: Int(virtualKey), char: nil, action: .tap, modifiers: modifiers)
        Task { try? await session.sendKey(key) }
    }

    /// Correlates by macro `id` (not envelope `ref`, which `ClientSession.invokeMacro` does not
    /// surface to callers — see `ConnectionManager`'s `macroResult` waiter bookkeeping).
    public func invokeMacro(id: UUID, confirmed: Bool) async throws -> MacroInvokeOutcome {
        guard let session = manager.activeSession else {
            throw ConnectionSinkError.notConnected
        }
        return try await manager.invokeMacroAwaitingResult(id: id, confirmed: confirmed, session: session)
    }

    public func requestMacroList() async throws -> [Macro] {
        // No on-demand "request macro list" wire message exists in the verified `ClientSession`
        // API (macroList is host-pushed on connect only, spec §5.5.6) — see final report
        // deviation. Returns the most recently pushed list.
        manager.latestMacroList?.macros ?? []
    }
}

public enum ConnectionSinkError: Error, Sendable, Equatable {
    case notConnected
}
