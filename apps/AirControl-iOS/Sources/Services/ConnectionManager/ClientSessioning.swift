// Services/ConnectionManager/ClientSessioning.swift
// A protocol wrapping the exact `AirControlCore.ClientSession` calls `ConnectionManager` uses, so
// tests can substitute a fake session instead of driving a real TLS/UDP handshake (this
// assignment's "Tests (simulator-safe, no network)" requirement). `ClientSession` is a concrete
// `actor` (not a protocol) in `AirControlCore`, so this is this module's own minimal seam over it —
// mirrors the pattern `ControlChannel`/`DatagramChannel` already use one layer down.
//
// Every requirement mirrors a real, verified `ClientSession` member 1:1 (see the doc comments on
// each for the spec citation `ClientSession` itself carries) — nothing here invents new
// behavior. `AirControlProtocol.Text` is spelled out to avoid colliding with `SwiftUI.Text`.

import Foundation
import AirControlCore
import AirControlCrypto
import AirControlProtocol

/// Everything `ConnectionManager`/`ConnectionSinks` call on a live `ClientSession`.
public protocol ClientSessioning: AnyObject, Sendable {
    nonisolated var events: AsyncStream<ClientEvent> { get }

    func connect(macroRevision: Int?) async throws -> ConnectedInfo
    func pair(url: PairingURL, macroRevision: Int?) async throws -> ConnectedInfo

    func sendClick(_ click: Click) async throws
    func sendScrollPhase(_ phase: ScrollPhase) async throws
    func sendModifiers(_ modifiers: Modifiers) async throws
    func sendKey(_ key: Key) async throws
    func sendText(_ text: AirControlProtocol.Text) async throws
    func sendDeleteBackward(_ deleteBackward: DeleteBackward) async throws
    func sendMediaKey(_ mediaKey: MediaKeyMessage) async throws
    func sendVolume(_ volume: Volume) async throws
    func invokeMacro(id: UUID, confirmed: Bool) async throws
    func sendRecenter() async throws
    func sendSettings(_ settings: Settings) async throws

    func sendHeartbeat() async throws
    func sendProbe() async throws
    func expireOutstandingProbeIfNeeded() async -> ProbeController.Mode

    func sendGoodbye(_ reason: GoodbyeReason) async throws
    func sendMotion(_ payload: MotionPayload) async throws
    func flushPendingMotionBatch() async throws
    func currentStats() async -> SessionStats
    func close(reason: GoodbyeReason) async
}

/// `ClientSession` already exposes every one of these members (verified before this agent started
/// writing code); this conformance is the only thing needed to treat it as `any ClientSessioning`.
extension ClientSession: ClientSessioning {}
