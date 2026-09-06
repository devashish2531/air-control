import Testing
@testable import AirControlCrypto

@Suite struct AirControlCryptoSmokeTests {
    @Test func moduleLinks() {
        #expect(AirControlCryptoModule.name == "AirControlCrypto")
    }
}
