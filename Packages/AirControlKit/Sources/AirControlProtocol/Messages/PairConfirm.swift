import Foundation

/// `pairConfirm` (H→C). spec §3.4.5: "`hostProof` b64u(32), `hostModel` str."
public struct PairConfirm: Codable, Sendable, Equatable {
    public var hostProof: B64UData
    public var hostModel: String

    public init(hostProof: B64UData, hostModel: String) {
        self.hostProof = hostProof
        self.hostModel = hostModel
    }
}
