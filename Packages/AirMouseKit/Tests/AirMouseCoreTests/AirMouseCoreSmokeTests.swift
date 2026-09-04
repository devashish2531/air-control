import Testing
@testable import AirMouseCore

@Suite struct AirMouseCoreSmokeTests {
    @Test func moduleLinks() {
        #expect(AirMouseCoreModule.name == "AirMouseCore")
    }
}
