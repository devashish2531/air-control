import Foundation
import AirMouseProtocol

/// User-facing error category a `CoreError` maps to, matching spec §9's `E-*` families at a
/// coarse level suitable for the apps to pick UI copy/icon without switching on every wire code.
public enum CoreErrorCategory: Sendable, Equatable {
    case pairing
    case authentication
    case protocolMismatch
    case network
    case rateLimited
    case macro
    case internalFailure
}

/// `AirMouseCore`'s local error type. Wraps/reclassifies `AirMouseProtocol.ProtocolError` and the
/// wire `ErrorPayload`/`ErrorCode` into the categories the apps show, per spec §9 ("Mismatch UX:
/// E-VERSION-* tells the user which side to update, never a silent failure").
public enum CoreError: Error, Sendable, Equatable {
    case protocolViolation(ProtocolError)
    case versionMismatch(min: Int, max: Int, peerVersion: String?)
    case pairingExpired
    case pairingInvalidProof
    case pairingTooManyDevices
    case pairingHostProofInvalid
    /// Not part of the original spec: the host answered a re-pairing attempt with
    /// `pairing.alreadyTrusted` (spec decision, see `HostSessionStateMachine`) — this peer's
    /// certificate is already trusted and there was no open pairing window to prove against.
    case pairingAlreadyTrusted
    case authUntrusted
    case authRevoked
    case rateLimited
    case macroBlockedByPolicy
    case sessionTimedOut
    case channelClosed
    /// A message arrived that made no sense for the phase the session is in (e.g. a malformed
    /// `sessionKey` payload) — distinct from `.internalFailure`, which is this process's own
    /// failure, not the peer's. `expected`/`got` are short, developer-facing descriptions (never
    /// secrets), matching `AppError.protocolMismatch`'s copy.
    case protocolMismatch(expected: String, got: String)
    case internalFailure(String)

    /// Coarse UI category (spec §9).
    public var category: CoreErrorCategory {
        switch self {
        case .protocolViolation: .protocolMismatch
        case .versionMismatch: .protocolMismatch
        case .pairingExpired, .pairingInvalidProof, .pairingTooManyDevices, .pairingHostProofInvalid, .pairingAlreadyTrusted: .pairing
        case .authUntrusted, .authRevoked: .authentication
        case .rateLimited: .rateLimited
        case .macroBlockedByPolicy: .macro
        case .sessionTimedOut, .channelClosed: .network
        case .protocolMismatch: .protocolMismatch
        case .internalFailure: .internalFailure
        }
    }

    /// The wire `ErrorCode` this local error corresponds to, where the spec defines one.
    public var wireCode: ErrorCode? {
        switch self {
        case .versionMismatch: .versionMismatch
        case .pairingExpired: .pairingExpired
        case .pairingInvalidProof: .pairingInvalidProof
        case .pairingTooManyDevices: .pairingTooManyDevices
        case .pairingAlreadyTrusted: .alreadyTrusted
        case .authUntrusted: .authUntrusted
        case .authRevoked: .authRevoked
        case .rateLimited: .rateLimited
        case .macroBlockedByPolicy: .macroBlockedByPolicy
        case .protocolViolation(let inner): inner.code
        default: nil
        }
    }

    /// Maps a received wire `ErrorPayload` to a `CoreError`, falling back to `.internalFailure`
    /// for a code this build does not recognize (spec §3.4.2 forward-compatibility rule).
    public init(wire payload: ErrorPayload) {
        switch payload.knownCode {
        case .versionMismatch: self = .versionMismatch(min: 0, max: 0, peerVersion: nil)
        case .pairingExpired: self = .pairingExpired
        case .pairingInvalidProof: self = .pairingInvalidProof
        case .pairingTooManyDevices: self = .pairingTooManyDevices
        case .alreadyTrusted: self = .pairingAlreadyTrusted
        case .authUntrusted: self = .authUntrusted
        case .authRevoked: self = .authRevoked
        case .rateLimited: self = .rateLimited
        case .macroBlockedByPolicy: self = .macroBlockedByPolicy
        case .frameTooLarge, .badFrame, .badMessage:
            self = .protocolViolation(.badMessage(reason: payload.message))
        case .internalError, .none:
            self = .internalFailure(payload.message)
        }
    }
}
