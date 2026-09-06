import Testing
@testable import AirControlProtocol

@Suite struct AirControlProtocolSmokeTests {
    @Test func moduleLinks() {
        #expect(AirControlProtocolModule.name == "AirControlProtocol")
    }
}
