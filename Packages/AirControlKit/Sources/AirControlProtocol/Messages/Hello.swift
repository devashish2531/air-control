import Foundation

/// `hello` (C→H, first message). spec §3.4.5 / §11.1.
public struct Hello: Codable, Sendable, Equatable {
    /// `protocol.min` / `protocol.max`: the client's supported protocol major version range.
    public struct ProtocolRange: Codable, Sendable, Equatable {
        public var min: Int
        public var max: Int

        public init(min: Int, max: Int) {
            self.min = min
            self.max = max
        }
    }

    /// `device.{name,model,os,app}`.
    public struct Device: Codable, Sendable, Equatable {
        /// `UIDevice.current.name`, ≤ 63 bytes.
        public var name: String
        /// e.g. `iPhone16,1`.
        public var model: String
        /// e.g. `iOS 18.6`.
        public var os: String
        /// The app's version string.
        public var app: String

        public init(name: String, model: String, os: String, app: String) {
            self.name = name
            self.model = model
            self.os = os
            self.app = app
        }
    }

    public var `protocol`: ProtocolRange
    public var capabilities: [String]
    public var device: Device
    /// `true` → the client expects `pairChallenge` next rather than `helloAck` directly.
    public var pairing: Bool
    /// Cached macro list revision for this host; host skips `macroList` if equal.
    public var macroRevision: Int?
    /// 60 or 120; informational.
    public var displayHz: Int

    public init(
        protocol: ProtocolRange,
        capabilities: [String],
        device: Device,
        pairing: Bool,
        macroRevision: Int? = nil,
        displayHz: Int
    ) {
        self.protocol = `protocol`
        self.capabilities = capabilities
        self.device = device
        self.pairing = pairing
        self.macroRevision = macroRevision
        self.displayHz = displayHz
    }
}
