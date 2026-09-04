import Testing
@testable import AirMouseCrypto

@Suite struct AirMouseCryptoSmokeTests {
    @Test func moduleLinks() {
        #expect(AirMouseCryptoModule.name == "AirMouseCrypto")
    }
}
