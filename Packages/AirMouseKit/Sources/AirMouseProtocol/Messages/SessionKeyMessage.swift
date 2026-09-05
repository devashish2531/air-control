import Foundation

/// `sessionKey` (H→C). spec §3.4.5: "`sessionID` int (u32), `secret` b64u(32), `validForMs` int
/// (14 400 000). See §3.5.3." Named `SessionKeyMessage` (not `SessionKey`) to leave `SessionKey`
/// free for `AirMouseCrypto`'s derived-key value type.
public struct SessionKeyMessage: Codable, Sendable, Equatable {
    public var sessionID: UInt32
    public var secret: B64UData
    /// Default 14 400 000 ms (4 hours); see `ProtocolConstants.sessionKeyValidForMsDefault`.
    public var validForMs: Int

    public init(sessionID: UInt32, secret: B64UData, validForMs: Int) {
        self.sessionID = sessionID
        self.secret = secret
        self.validForMs = validForMs
    }
}
