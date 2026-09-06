import Foundation

/// `error` (both directions). spec §3.4.5: "`code` str (dotted namespace: `protocol.*`, `auth.*`,
/// `pairing.*`, `rate.*`, `host.*`, `macro.*`, `internal`), `message` str (English,
/// developer-facing; the client maps `code` to localized copy), `ref` int?, `fatal` bool
/// (true → sender closes after flushing)."
///
/// Named `ErrorPayload` rather than `ProtocolError` (as the spec's illustrative Swift sketch in
/// §3.4.7 names it) to avoid a clash with this module's `ProtocolError`, the local `Error`/
/// `LocalizedError` type this package's own decoding, framing and validation APIs throw (task
/// requirement) — the two are different roles (wire payload vs. local Swift error) that would be
/// confusing to share one name.
///
/// `code` is a plain `String`, not `ErrorCode`, so an error code this build does not recognize
/// still round-trips instead of failing to decode (spec §3.4.2 forward-compatibility rule); use
/// `knownCode` to recover a typed value when the code is one this build knows.
public struct ErrorPayload: Codable, Sendable, Equatable {
    public var code: String
    public var message: String
    public var ref: UInt32?
    public var fatal: Bool

    public init(code: String, message: String, ref: UInt32? = nil, fatal: Bool) {
        self.code = code
        self.message = message
        self.ref = ref
        self.fatal = fatal
    }

    public init(code: ErrorCode, message: String, ref: UInt32? = nil, fatal: Bool) {
        self.init(code: code.rawValue, message: message, ref: ref, fatal: fatal)
    }

    /// `code` reinterpreted as a known `ErrorCode`, or `nil` if this build does not recognize it.
    public var knownCode: ErrorCode? { ErrorCode(rawValue: code) }
}
