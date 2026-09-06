import Foundation
import AirControlProtocol

/// Which channel a motion payload actually arrived on (spec §3.5.9: the host's motion pipeline
/// tags TCP-fallback payloads with `channel = tcp` for diagnostics).
public enum MotionChannelKind: Sendable, Equatable {
    case udp
    case tcp
}

/// One accepted motion payload, ready for the host's `AccelerationCurve`/`ScrollGain`/
/// `DisplayClamp` pipeline (spec §3.5.4's "Datagrams within the 8-window are applied in arrival
/// order").
public struct MotionDeltaEvent: Sendable, Equatable {
    public var payload: MotionPayload
    public var channel: MotionChannelKind
    /// `false` if this datagram was accepted (authenticated, not a replay) but is more than 8
    /// counters behind the highest *applied* counter and must not move the pointer (spec §3.5.4).
    public var shouldApply: Bool

    public init(payload: MotionPayload, channel: MotionChannelKind, shouldApply: Bool) {
        self.payload = payload
        self.channel = channel
        self.shouldApply = shouldApply
    }
}

/// Events `HostSession` delivers to the app's `EventInjector` via its
/// `events: AsyncStream<HostEvent>` (arch §3.1's public API table; assignment §3 "Host/").
public enum HostEvent: Sendable, Equatable {
    case motion(MotionDeltaEvent)
    case click(Click)
    case scrollPhase(ScrollPhase)
    case modifiers(Modifiers)
    case key(Key)
    case text(Text)
    case deleteBackward(DeleteBackward)
    case mediaKey(MediaKeyMessage)
    case volume(Volume)
    /// `messageID` is the envelope `i` of the triggering `macroInvoke`, used as `macroResult.ref`.
    case macroInvoke(MacroInvoke, messageID: UInt32)
    case recenter
    case settings(Settings)
    /// A device authenticated (spec §3.2's pairing/reconnect flows both end here). `viaPairingFlow`
    /// is `true` when this authentication came from a completed `pairChallenge`/`pairProof`/
    /// `pairConfirm` round trip — whether the peer's certificate was unknown (first-time pairing)
    /// or already known (spec decision, not in §3.2/§3.3: re-pairing an already-trusted device,
    /// e.g. re-scanning "Pair new device"'s QR, succeeds instead of mismatching the client's
    /// pairing-flow expectations — see `HostSessionStateMachine`'s `.tlsAccepted(.known)`/
    /// `.helloReceivedPairingTrue` case) — and `false` for a plain trusted `hello { pairing:
    /// false }` reconnect that never touched the pairing window at all.
    case clientAuthenticated(device: Hello.Device, viaPairingFlow: Bool)
    case clientDisconnected(reason: String)
    /// Every held input this session was tracking has just been released (stale timeout, close,
    /// or the 60 s watchdog) — the app's `EventInjector` must post the corresponding "up" events.
    case releaseHeldInputs([HeldInputItem])
}
