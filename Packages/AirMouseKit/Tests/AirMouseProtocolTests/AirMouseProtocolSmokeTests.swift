import Testing
@testable import AirMouseProtocol

@Suite struct AirMouseProtocolSmokeTests {
    @Test func moduleLinks() {
        #expect(AirMouseProtocolModule.name == "AirMouseProtocol")
    }
}
