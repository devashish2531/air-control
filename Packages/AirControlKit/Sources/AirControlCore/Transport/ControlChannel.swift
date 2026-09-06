import Foundation
import AirControlCrypto

/// The control (TCP/TLS) channel abstraction `AirControlCore` drives; implemented by the apps and
/// `aircontrol-cli` with `Network.framework` (arch §3.1 rule 4/6: "Core never imports `Network`").
///
/// A `ControlChannel` carries already-framed bytes (the output of
/// `AirControlProtocol.FrameEncoder`/input to `FrameDecoder`, spec §3.4.1) — `AirControlCore` owns
/// framing and envelope (de)serialization; the transport only moves bytes over TLS 1.3 and
/// exposes the two pieces of TLS state the pairing/reconnect handshake needs (spec §3.2.1,
/// §3.2.3): the peer's leaf certificate fingerprint and the TLS exporter secret for channel
/// binding.
public protocol ControlChannel: Sendable {
    /// Sends one already-framed control frame (`FrameEncoder` output).
    func send(_ frame: Data) async throws
    /// Complete frames as produced by `FrameDecoder`; finishes on close/error.
    var incoming: AsyncThrowingStream<Data, any Error> { get }
    /// Peer TLS leaf certificate fingerprint, available after handshake.
    var peerFingerprint: Fingerprint? { get async }
    /// TLS exporter secret (32 bytes) for channel binding, if the platform exposes it; nil → contingency path per spec §3.2.
    func exporterSecret() async -> Data?
    func close() async
}

/// The datagram (UDP) channel abstraction for the motion path (spec §3.5). Implemented by the
/// apps with `Network.framework`; `AirControlCore` only seals/opens/coalesces payloads and hands
/// raw 44-byte datagrams to `send`.
public protocol DatagramChannel: Sendable {
    func send(_ datagram: Data) throws
    var incoming: AsyncStream<Data> { get }
    func close()
}

/// A caller-supplied factory that opens a `DatagramChannel` to the host's `helloAck.udpPort` (the
/// port is only known once `helloAck` arrives, so this cannot be constructed up front the way
/// `ControlChannel` is — `AirControlCore` never imports `Network`, so it cannot open the UDP
/// connection itself). Not part of the two required transport protocol shapes; a minimal seam
/// `ClientSession` needs so the app can hand over UDP connection creation lazily. See the
/// `ClientSession` doc comment / final report for this deviation.
public typealias DatagramChannelProvider = @Sendable (_ udpPort: Int) async throws -> any DatagramChannel
