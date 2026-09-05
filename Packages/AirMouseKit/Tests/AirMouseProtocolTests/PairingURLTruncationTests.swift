import Foundation
import Testing
@testable import AirMouseProtocol

@Suite struct PairingURLTruncationTests {
    /// Regression: a multi-homed host with more than `maxAddresses` interface addresses must yield a
    /// pairing URL with the first `maxAddresses` entries rather than throwing (spec §3.1.3).
    @Test func truncatingToFitTrimsAddressCountBeforeValidating() throws {
        let many = (1...14).map { "192.168.1.\($0)" }
        let url = try PairingURL.truncatingToFit(
            version: ProtocolConstants.protocolVersion,
            hostID: Data(repeating: 0xAB, count: 16),
            hostName: "Multi-homed Mac",
            addresses: many,
            tcpPort: 47800,
            udpPort: 47800,
            fingerprint: Data(repeating: 0xCD, count: 32),
            secret: Data(repeating: 0xEF, count: 16)
        )
        #expect(url.addresses.count <= PairingURL.maxAddresses)
        #expect(url.addresses.first == "192.168.1.1")
        #expect(try url.formatted().utf8.count <= PairingURL.maxURLLength)
    }
}
