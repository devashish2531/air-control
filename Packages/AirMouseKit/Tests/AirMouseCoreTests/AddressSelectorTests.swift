import Testing
@testable import AirMouseCore

@Suite struct AddressSelectorTests {
    @Test func privateIPv4RangesAreAllowed() {
        #expect(AddressSelector.isPrivateAddress("10.0.0.1"))
        #expect(AddressSelector.isPrivateAddress("192.168.1.5"))
        #expect(AddressSelector.isPrivateAddress("172.16.0.1"))
        #expect(AddressSelector.isPrivateAddress("172.20.10.5")) // hotspot subnet, within 172.16/12
        #expect(AddressSelector.isPrivateAddress("172.31.255.255"))
        #expect(AddressSelector.isPrivateAddress("169.254.1.1"))
        #expect(AddressSelector.isPrivateAddress("127.0.0.1"))
    }

    @Test func routableIPv4IsNotPrivate() {
        #expect(!AddressSelector.isPrivateAddress("8.8.8.8"))
        #expect(!AddressSelector.isPrivateAddress("172.32.0.1")) // just outside 172.16/12
        #expect(!AddressSelector.isPrivateAddress("1.1.1.1"))
    }

    @Test func privateIPv6RangesAreAllowed() {
        #expect(AddressSelector.isPrivateAddress("fe80::1"))
        #expect(AddressSelector.isPrivateAddress("fc00::1"))
        #expect(AddressSelector.isPrivateAddress("fd12:3456::1"))
        #expect(AddressSelector.isPrivateAddress("::1"))
    }

    @Test func routableIPv6IsNotPrivate() {
        #expect(!AddressSelector.isPrivateAddress("2001:4860:4860::8888"))
    }

    @Test func orderConcatenatesBonjourThenLastKnownThenQR() {
        let bonjour = AddressSelector.Candidate(address: "192.168.1.10", port: 47800, source: .bonjour)
        let lastKnown = AddressSelector.Candidate(address: "192.168.1.11", port: 47800, source: .lastKnown)
        let qr = AddressSelector.Candidate(address: "192.168.1.12", port: 47800, source: .qr)
        let ordered = AddressSelector.order(bonjour: bonjour, lastKnown: [lastKnown], qr: [qr])
        #expect(ordered.map(\.address) == ["192.168.1.10", "192.168.1.11", "192.168.1.12"])
    }

    @Test func nonPrivateAddressIsSkippedUnlessFromQR() {
        let routableLastKnown = AddressSelector.Candidate(address: "8.8.8.8", port: 47800, source: .lastKnown)
        let routableQR = AddressSelector.Candidate(address: "8.8.4.4", port: 47800, source: .qr)
        let ordered = AddressSelector.order(bonjour: nil, lastKnown: [routableLastKnown], qr: [routableQR])
        #expect(ordered.map(\.address) == ["8.8.4.4"])
    }

    @Test func duplicateAddressPortIsDeduplicated() {
        let a = AddressSelector.Candidate(address: "192.168.1.10", port: 47800, source: .bonjour)
        let b = AddressSelector.Candidate(address: "192.168.1.10", port: 47800, source: .lastKnown)
        let ordered = AddressSelector.order(bonjour: a, lastKnown: [b], qr: [])
        #expect(ordered.count == 1)
        #expect(ordered.first?.source == .bonjour)
    }

    @Test func noBonjourResultIsOmitted() {
        let lastKnown = AddressSelector.Candidate(address: "192.168.1.11", port: 47800, source: .lastKnown)
        let ordered = AddressSelector.order(bonjour: nil, lastKnown: [lastKnown], qr: [])
        #expect(ordered == [lastKnown])
    }

    @Test func ipv6DetectionOnCandidate() {
        let candidate = AddressSelector.Candidate(address: "fe80::1", port: 1, source: .qr)
        #expect(candidate.isIPv6)
        let v4 = AddressSelector.Candidate(address: "10.0.0.1", port: 1, source: .qr)
        #expect(!v4.isIPv6)
    }
}
