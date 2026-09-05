import Foundation

/// `pairChallenge` (H→C). spec §3.4.5: "`nonce` b64u(16), `hostID` b64u(16), `hostName` str,
/// `expiresInMs` int."
public struct PairChallenge: Codable, Sendable, Equatable {
    public var nonce: B64UData
    public var hostID: B64UData
    public var hostName: String
    public var expiresInMs: Int

    public init(nonce: B64UData, hostID: B64UData, hostName: String, expiresInMs: Int) {
        self.nonce = nonce
        self.hostID = hostID
        self.hostName = hostName
        self.expiresInMs = expiresInMs
    }
}
