import Testing
@testable import AirControlCore

@Suite struct AirControlCoreSmokeTests {
    @Test func moduleLinks() {
        #expect(AirControlCoreModule.name == "AirControlCore")
    }
}
