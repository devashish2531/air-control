// Services/MotionPublisher/MotionDatagramSink.swift
// Output boundary of `MotionPublisher` (arch §3.2 Motion subsystem / §4.2(b) sequence diagram:
// "MP->>NW: send(...)"). This module owns no networking (CLAUDE.md: only the two apps and
// airmouse-cli import Network) and no crypto (AirMouseCrypto is a different layer) — sealing the
// 16-byte payload into the 44-byte AEAD datagram and handing it to `NWConnection`/
// `NWDatagramTransport` is the Connection agent's `ClientSession` (AirMouseCore). This protocol is
// the one thing `MotionPublisher` needs from that side.

import AirMouseProtocol

/// Receives one already-packed, plaintext `MotionPayload` per flush (spec §3.5.2). Conformer's
/// job: `AirMouseCrypto.seal` it into the 44-byte UDP datagram (§3.5.1) and send it — or, while in
/// TCP fallback (§3.5.8), batch it into a `kind = 0x02` frame (`MotionBatch`, §3.5.9) instead.
/// Intentionally synchronous and `Sendable`: it is called from `MotionPublisher`'s own executor
/// and must not block it — a conformer that needs to hop elsewhere (e.g. onto its own `net`
/// actor) should do so by handing the payload to something like an unbounded internal queue and
/// returning immediately, not by awaiting inside this call.
public protocol MotionDatagramSink: Sendable {
    func sendMotion(_ payload: MotionPayload)
}

/// Default stand-in until the Connection agent's `ClientSession`-backed sink is wired through
/// `TouchpadFeature.make(environment:motion:controlSink:)`.
public struct NoOpMotionDatagramSink: MotionDatagramSink {
    public init() {}
    public func sendMotion(_ payload: MotionPayload) {}
}
