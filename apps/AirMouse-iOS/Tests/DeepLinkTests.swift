// Tests/DeepLinkTests.swift
// `DeepLink.isPairingURL` recognises `airmouse://pair?...` (spec §4.1.2) case-insensitively and
// rejects everything else, including URLs that merely resemble it.

import Testing
import Foundation
@testable import Air_Mouse

@Suite struct DeepLinkTests {
    @Test func recognisesPairingURL() {
        let url = URL(string: "airmouse://pair?v=1&fp=abcd&addr=192.168.1.5:47800")!
        #expect(DeepLink.isPairingURL(url))
    }

    @Test func isCaseInsensitiveOnSchemeAndHost() {
        let url = URL(string: "AirMouse://PAIR?v=1")!
        #expect(DeepLink.isPairingURL(url))
    }

    @Test func rejectsWrongScheme() {
        let url = URL(string: "https://pair?v=1")!
        #expect(!DeepLink.isPairingURL(url))
    }

    @Test func rejectsWrongHost() {
        let url = URL(string: "airmouse://notpair?v=1")!
        #expect(!DeepLink.isPairingURL(url))
    }

    @Test func rejectsMissingHost() {
        let url = URL(string: "airmouse:pair")!
        #expect(!DeepLink.isPairingURL(url))
    }

    @Test func rejectsUnrelatedURL() {
        let url = URL(string: "https://github.com/air-mouse/air-mouse")!
        #expect(!DeepLink.isPairingURL(url))
    }
}
