// Tests/DeepLinkTests.swift
// `DeepLink.isPairingURL` recognises `aircontrol://pair?...` (spec §4.1.2) case-insensitively and
// rejects everything else, including URLs that merely resemble it.

import Testing
import Foundation
@testable import Air_Control

@Suite struct DeepLinkTests {
    @Test func recognisesPairingURL() {
        let url = URL(string: "aircontrol://pair?v=1&fp=abcd&addr=192.168.1.5:47800")!
        #expect(DeepLink.isPairingURL(url))
    }

    @Test func isCaseInsensitiveOnSchemeAndHost() {
        let url = URL(string: "AirControl://PAIR?v=1")!
        #expect(DeepLink.isPairingURL(url))
    }

    @Test func rejectsWrongScheme() {
        let url = URL(string: "https://pair?v=1")!
        #expect(!DeepLink.isPairingURL(url))
    }

    @Test func rejectsWrongHost() {
        let url = URL(string: "aircontrol://notpair?v=1")!
        #expect(!DeepLink.isPairingURL(url))
    }

    @Test func rejectsMissingHost() {
        let url = URL(string: "aircontrol:pair")!
        #expect(!DeepLink.isPairingURL(url))
    }

    @Test func rejectsUnrelatedURL() {
        let url = URL(string: "https://github.com/air-control/air-control")!
        #expect(!DeepLink.isPairingURL(url))
    }
}
