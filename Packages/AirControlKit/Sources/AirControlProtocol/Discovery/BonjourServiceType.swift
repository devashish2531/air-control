import Foundation

/// The Bonjour service types the host registers and the client browses. spec §3.1.1: "The host
/// registers `_aircontrol._tcp` (control) and `_aircontrol._udp` (motion) in the local domain with the
/// same instance name and the same TXT record (FR-DP-001). The client browses only
/// `_aircontrol._tcp`... `includePeerToPeer = false` on both sides (no AWDL)."
public enum BonjourServiceType {
    /// The control-channel service type; the only one the client browses.
    public static let control = "_aircontrol._tcp"
    /// The motion-channel service type; registered so `NSBonjourServices` is complete and
    /// third-party tooling can see both ports, but never browsed by the client (spec §3.1.1).
    public static let motion = "_aircontrol._udp"
    /// Bonjour's local domain.
    public static let domain = "local."
}
