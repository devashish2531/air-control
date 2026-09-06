import Foundation

/// Minimal, dependency-free validation of IPv4/IPv6 address literals for `PairingURL`'s `a`
/// parameter (spec §3.1.3: "comma-separated literal IPv4 / IPv6 (no brackets, no zone)"). This
/// module cannot import `Network` (architecture §3.1 rule 1: "Foundation only"), so this is a
/// hand-rolled syntactic check — enough to reject garbage and distinguish the two families, not a
/// full RFC 4291/791 conformance suite.
public enum IPLiteral {
    /// `true` if `string` is four dot-separated decimal octets (`0...255`, no leading zeros other
    /// than the literal "0", no whitespace).
    public static func isValidIPv4(_ string: String) -> Bool {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isASCII) , part.allSatisfy(\.isNumber) else {
                return false
            }
            guard let value = Int(part), (0...255).contains(value) else { return false }
            if part.count > 1 && part.first == "0" { return false }
            return true
        }
    }

    /// `true` if `string` looks like an IPv6 literal: 2–8 colon-separated groups of 1–4 hex
    /// digits, at most one `::` compression, no brackets, no zone (`%eth0`) suffix (the spec
    /// requires "no brackets, no zone").
    public static func isValidIPv6(_ string: String) -> Bool {
        guard !string.isEmpty, !string.contains("["), !string.contains("]"), !string.contains("%") else {
            return false
        }
        let compressionCount = string.components(separatedBy: "::").count - 1
        guard compressionCount <= 1 else { return false }

        let groups = string.components(separatedBy: ":")
        // "::" splits into an empty component on each side it touches; every other component must
        // be a valid 1-4 digit hex group.
        var sawEmpty = false
        for group in groups {
            if group.isEmpty {
                sawEmpty = true
                continue
            }
            guard group.count <= 4, group.allSatisfy(\.isHexDigit) else { return false }
        }
        // A bare "::" is valid; otherwise an empty group is only legal as part of "::".
        if sawEmpty && compressionCount == 0 && string != "::" { return false }
        guard groups.count >= 2, groups.count <= 8 else { return false }
        return true
    }

    /// `true` if `string` validates as either family.
    public static func isValid(_ string: String) -> Bool {
        isValidIPv4(string) || isValidIPv6(string)
    }
}
