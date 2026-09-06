// App/DeepLink.swift
// Recognises `aircontrol://pair?...` URLs (spec §4.1.2) so `RootTabView` can forward them to the
// `PairingRouting` slot. Parsing the query payload itself (`v`, addresses, fingerprint, secret —
// spec §3.1.3) is the Pairing agent's job; this only decides "is this a pairing URL at all",
// which is pure and easy to unit test without any SwiftUI/environment plumbing.

import Foundation

public enum DeepLink {
    /// `true` for any URL whose scheme is `aircontrol` and host is `pair`, case-insensitively.
    /// Malformed *payloads* (bad `v`, missing fields) are still "pairing URLs" for routing
    /// purposes — E-PAIR-URL/E-PAIR-VERSION (spec §9) are the Pairing feature's presentation
    /// concern once it inspects the query, not this shell-level scheme/host check.
    public static func isPairingURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "aircontrol" else { return false }
        guard let host = url.host?.lowercased(), host == "pair" else { return false }
        return true
    }
}
