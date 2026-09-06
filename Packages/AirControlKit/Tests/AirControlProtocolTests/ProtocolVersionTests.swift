import Foundation
import Testing
@testable import AirControlProtocol

@Suite struct ProtocolVersionTests {
    @Test func negotiatesHighestCommonVersion() {
        let negotiated = ProtocolVersion.negotiate(clientMin: 1, clientMax: 2, hostMin: 1, hostMax: 1)
        #expect(negotiated == ProtocolVersion(1))
    }

    @Test func negotiatesHigherSharedVersionWhenBothSupportIt() {
        let negotiated = ProtocolVersion.negotiate(clientMin: 1, clientMax: 3, hostMin: 2, hostMax: 3)
        #expect(negotiated == ProtocolVersion(3))
    }

    @Test func returnsNilWhenRangesDoNotOverlap() {
        let negotiated = ProtocolVersion.negotiate(clientMin: 2, clientMax: 3, hostMin: 0, hostMax: 1)
        #expect(negotiated == nil)
    }

    @Test func exactSingleVersionMatch() {
        let negotiated = ProtocolVersion.negotiate(clientMin: 1, clientMax: 1, hostMin: 1, hostMax: 1)
        #expect(negotiated == ProtocolVersion(1))
    }

    @Test func comparable() {
        #expect(ProtocolVersion(1) < ProtocolVersion(2))
        #expect(!(ProtocolVersion(2) < ProtocolVersion(2)))
    }

    @Test func currentMatchesProtocolConstants() {
        #expect(ProtocolVersion.current.rawValue == ProtocolConstants.protocolVersion)
    }
}
