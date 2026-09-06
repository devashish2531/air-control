import Foundation

/// `helloAck` (H→C). spec §3.4.5 / §11.1.
public struct HelloAck: Codable, Sendable, Equatable {
    /// `host.{name,model,os,helper,id}`.
    public struct Host: Codable, Sendable, Equatable {
        public var name: String
        public var model: String
        public var os: String
        /// The helper app's version string.
        public var helper: String
        public var id: B64UData

        public init(name: String, model: String, os: String, helper: String, id: B64UData) {
            self.name = name
            self.model = model
            self.os = os
            self.helper = helper
            self.id = id
        }
    }

    /// The chosen (negotiated) protocol version; all subsequent `v` envelope fields equal it
    /// (spec §3.4.4).
    public var `protocol`: Int
    public var capabilities: [String]
    public var host: Host
    public var udpPort: Int
    /// Default 500 (`ProtocolConstants.helloAckHeartbeatMsDefault`).
    public var heartbeatMs: Int
    /// Default 2000 (`ProtocolConstants.helloAckSessionTimeoutMsDefault`).
    public var sessionTimeoutMs: Int
    /// Default 16384 (`ProtocolConstants.helloAckMaxTextBytesDefault`).
    public var maxTextBytes: Int
    /// Other connected devices, not counting this one.
    public var sessionCount: Int

    public init(
        protocol: Int,
        capabilities: [String],
        host: Host,
        udpPort: Int,
        heartbeatMs: Int,
        sessionTimeoutMs: Int,
        maxTextBytes: Int,
        sessionCount: Int
    ) {
        self.protocol = `protocol`
        self.capabilities = capabilities
        self.host = host
        self.udpPort = udpPort
        self.heartbeatMs = heartbeatMs
        self.sessionTimeoutMs = sessionTimeoutMs
        self.maxTextBytes = maxTextBytes
        self.sessionCount = sessionCount
    }
}
